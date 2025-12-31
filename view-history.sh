#!/bin/bash

# =============================================================================
# Script de Visualizacion de Historico SSD
# =============================================================================
# Soporta: APPLE (interno) y SAMSUNG (externo)
# Uso: ./view-history.sh [--disk=apple|samsung|all]
# =============================================================================

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuracion
source "$SCRIPT_DIR/config.sh"

# -----------------------------------------------------------------------------
# Parsear argumentos
# -----------------------------------------------------------------------------
FILTER_DISK=""

for arg in "$@"; do
    case "$arg" in
        --disk=all|--disk=ALL|-d=all)
            FILTER_DISK="ALL"
            ;;
        --disk=apple|--disk=APPLE|-d=apple|-d=APPLE)
            FILTER_DISK="APPLE"
            ;;
        --disk=samsung|--disk=SAMSUNG|-d=samsung|-d=SAMSUNG)
            FILTER_DISK="SAMSUNG"
            ;;
    esac
done

# Por defecto mostrar todos
[ -z "$FILTER_DISK" ] && FILTER_DISK="ALL"

# -----------------------------------------------------------------------------
# Verificar archivo de historico
# -----------------------------------------------------------------------------
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}✗ No hay historico disponible${NC}"
    echo -e "Ejecuta primero: ${WHITE}./track-ssd-history.sh${NC}"
    exit 1
fi

# Verificar formato del CSV
first_column=$(head -1 "$LOG_FILE" | cut -d',' -f1)
if [ "$first_column" != "disk_name" ]; then
    echo -e "${YELLOW}⚠ El archivo de historico tiene el formato antiguo${NC}"
    echo -e "Ejecuta ${WHITE}./track-ssd-history.sh${NC} para migrar automaticamente"
    exit 1
fi

# -----------------------------------------------------------------------------
# Funciones de visualizacion
# -----------------------------------------------------------------------------

show_header() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Historico de Salud - Sistema Multi-Disco                            ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"
}

get_filtered_data() {
    if [ "$FILTER_DISK" = "ALL" ]; then
        tail -n +2 "$LOG_FILE"
    else
        grep "^$FILTER_DISK," "$LOG_FILE"
    fi
}

show_overview() {
    # Contar registros
    local total_records=$(tail -n +2 "$LOG_FILE" | wc -l | xargs)
    local apple_records=$(grep "^APPLE," "$LOG_FILE" | wc -l | xargs)
    local samsung_records=$(grep "^SAMSUNG," "$LOG_FILE" | wc -l | xargs)

    echo -e "${BOLD}Resumen del Historico:${NC}"
    echo -e "  Total de registros: ${WHITE}$total_records${NC}"
    echo -e "  Registros APPLE: ${WHITE}$apple_records${NC}"
    echo -e "  Registros SAMSUNG: ${WHITE}$samsung_records${NC}"
    echo -e "  Filtro actual: ${WHITE}$FILTER_DISK${NC}\n"

    # Obtener rango de fechas
    local filtered_data=$(get_filtered_data)
    if [ -n "$filtered_data" ]; then
        local first_date=$(echo "$filtered_data" | head -1 | cut -d',' -f3)
        local last_date=$(echo "$filtered_data" | tail -1 | cut -d',' -f3)
        echo -e "${BOLD}Periodo:${NC} ${WHITE}$first_date${NC} → ${WHITE}$last_date${NC}\n"
    fi
}

show_recent_records() {
    echo -e "${BOLD}${BLUE}▶ Ultimos 15 Registros${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -e "${BOLD}Disco    Fecha                Temp    Desgaste  Horas   Apagados  Estado${NC}"
    echo "─────────────────────────────────────────────────────────────────────────"

    get_filtered_data | tail -15 | tac | while IFS=',' read -r disk_name timestamp date hours cycles unsafe temp temp1 temp2 wear spare written read errors log_errors status; do
        # Colorear temperatura
        local temp_color=$WHITE
        if [ -n "$temp" ] && [ "$temp" != "" ]; then
            if [ "$temp" -lt 50 ] 2>/dev/null; then
                temp_color=$GREEN
            elif [ "$temp" -lt 70 ] 2>/dev/null; then
                temp_color=$YELLOW
            else
                temp_color=$RED
            fi
        fi

        # Colorear estado
        local status_color=$GREEN
        if [ "$status" != "PASSED" ]; then
            status_color=$RED
        fi

        # Formatear valores
        local temp_str="${temp:-N/A}"
        [ "$temp_str" != "N/A" ] && temp_str="${temp}°C"

        local wear_str="${wear:-N/A}"
        [ "$wear_str" != "N/A" ] && wear_str="${wear}%"

        local hours_str="${hours:-N/A}"
        [ "$hours_str" != "N/A" ] && hours_str="${hours}h"

        local unsafe_str="${unsafe:-N/A}"

        printf "${CYAN}%-8s${NC} ${WHITE}%-20s${NC} ${temp_color}%-7s${NC} %-9s %-7s %-9s ${status_color}%-8s${NC}\n" \
            "$disk_name" "$date" "$temp_str" "$wear_str" "$hours_str" "$unsafe_str" "$status"
    done
}

show_temperature_graph() {
    echo -e "\n${BOLD}${BLUE}▶ Evolucion de Temperatura (°C)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Obtener estadisticas de temperatura
    local temps=$(get_filtered_data | cut -d',' -f7 | grep -v '^$' | grep -v '^[^0-9]')

    if [ -z "$temps" ]; then
        echo -e "  ${YELLOW}No hay datos de temperatura disponibles${NC}\n"
        return
    fi

    local min_temp=$(echo "$temps" | sort -n | head -1)
    local max_temp=$(echo "$temps" | sort -n | tail -1)

    echo -e "Rango: ${WHITE}${min_temp}°C${NC} - ${WHITE}${max_temp}°C${NC}\n"

    # Mostrar ultimas 20 mediciones como grafico de barras
    get_filtered_data | tail -20 | while IFS=',' read -r disk_name timestamp date hours cycles unsafe temp temp1 temp2 wear spare written read errors log_errors status; do
        if [ -n "$temp" ] && [ "$temp" != "" ]; then
            # Calcular longitud de barra
            local bar_length=$(echo "scale=0; ($temp * 40) / 70" | bc 2>/dev/null || echo "0")

            # Color segun temperatura
            local color=$GREEN
            if [ "$temp" -ge 60 ] 2>/dev/null; then
                color=$RED
            elif [ "$temp" -ge 50 ] 2>/dev/null; then
                color=$YELLOW
            fi

            # Dibujar barra
            local date_short=$(echo "$date" | cut -d' ' -f1 | cut -d'-' -f2-)
            printf "${CYAN}%-8s${NC} %-10s ${color}" "$disk_name" "$date_short"
            for ((i=0; i<bar_length; i++)); do
                printf "█"
            done
            printf "${NC} ${WHITE}${temp}°C${NC}\n"
        fi
    done
}

show_statistics() {
    echo -e "\n${BOLD}${BLUE}▶ Estadisticas por Disco${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    for disk in "APPLE" "SAMSUNG"; do
        local disk_data=$(grep "^$disk," "$LOG_FILE")
        local record_count=$(echo "$disk_data" | grep -c "^$disk," 2>/dev/null || echo "0")

        if [ "$record_count" -gt 0 ]; then
            echo -e "${BOLD}${MAGENTA}=== $disk ===${NC}\n"

            # Primera y ultima medicion
            local first_record=$(echo "$disk_data" | head -1)
            local last_record=$(echo "$disk_data" | tail -1)

            local first_date=$(echo "$first_record" | cut -d',' -f3)
            local last_date=$(echo "$last_record" | cut -d',' -f3)

            echo -e "  Registros: ${WHITE}$record_count${NC}"
            echo -e "  Primer registro: ${WHITE}$first_date${NC}"
            echo -e "  Ultimo registro: ${WHITE}$last_date${NC}"

            # Temperatura
            local temps=$(echo "$disk_data" | cut -d',' -f7 | grep -v '^$')
            if [ -n "$temps" ]; then
                local avg_temp=$(echo "$temps" | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "N/A"}')
                local min_temp=$(echo "$temps" | sort -n | head -1)
                local max_temp=$(echo "$temps" | sort -n | tail -1)

                echo -e "\n  ${BOLD}Temperaturas:${NC}"
                echo -e "    Promedio: ${WHITE}${avg_temp}°C${NC}"
                echo -e "    Minima: ${WHITE}${min_temp}°C${NC}"
                echo -e "    Maxima: ${WHITE}${max_temp}°C${NC}"
            fi

            # Desgaste
            local first_wear=$(echo "$first_record" | cut -d',' -f10)
            local last_wear=$(echo "$last_record" | cut -d',' -f10)

            if [ -n "$first_wear" ] && [ -n "$last_wear" ]; then
                local wear_change=$(echo "$last_wear - $first_wear" | bc 2>/dev/null || echo "0")
                echo -e "\n  ${BOLD}Desgaste:${NC}"
                echo -e "    Inicial: ${WHITE}${first_wear}%${NC}"
                echo -e "    Actual: ${WHITE}${last_wear}%${NC}"
                echo -e "    Cambio: ${WHITE}+${wear_change}%${NC}"
            fi

            # Horas de encendido
            local first_hours=$(echo "$first_record" | cut -d',' -f4)
            local last_hours=$(echo "$last_record" | cut -d',' -f4)

            if [ -n "$first_hours" ] && [ -n "$last_hours" ]; then
                local hours_change=$((last_hours - first_hours))
                echo -e "\n  ${BOLD}Horas de Encendido:${NC}"
                echo -e "    Inicial: ${WHITE}${first_hours}h${NC}"
                echo -e "    Actual: ${WHITE}${last_hours}h${NC}"
                echo -e "    Cambio: ${WHITE}+${hours_change}h${NC}"
            fi

            # Apagados inseguros
            local first_unsafe=$(echo "$first_record" | cut -d',' -f6)
            local last_unsafe=$(echo "$last_record" | cut -d',' -f6)

            if [ -n "$first_unsafe" ] && [ -n "$last_unsafe" ]; then
                local unsafe_change=$((last_unsafe - first_unsafe))
                echo -e "\n  ${BOLD}Apagados Inseguros:${NC}"
                if [ "$unsafe_change" -gt 0 ]; then
                    echo -e "    Inicial: ${WHITE}${first_unsafe}${NC}"
                    echo -e "    Actual: ${WHITE}${last_unsafe}${NC}"
                    echo -e "    Nuevos: ${YELLOW}+${unsafe_change}${NC}"
                else
                    echo -e "    Total: ${WHITE}${last_unsafe}${NC} ${GREEN}(sin cambios)${NC}"
                fi
            fi

            echo ""
        fi
    done
}

show_alerts() {
    echo -e "${BOLD}${BLUE}▶ Analisis de Tendencias${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    local alerts=0

    for disk in "APPLE" "SAMSUNG"; do
        local disk_data=$(grep "^$disk," "$LOG_FILE")
        local record_count=$(echo "$disk_data" | grep -c "^$disk," 2>/dev/null || echo "0")

        if [ "$record_count" -gt 1 ]; then
            local first_record=$(echo "$disk_data" | head -1)
            local last_record=$(echo "$disk_data" | tail -1)

            # Verificar aumento en apagados inseguros
            local first_unsafe=$(echo "$first_record" | cut -d',' -f6)
            local last_unsafe=$(echo "$last_record" | cut -d',' -f6)

            if [ -n "$first_unsafe" ] && [ -n "$last_unsafe" ]; then
                local unsafe_change=$((last_unsafe - first_unsafe))
                if [ "$unsafe_change" -gt 5 ]; then
                    echo -e "  ${YELLOW}⚠${NC} [$disk] Se detectaron ${YELLOW}$unsafe_change${NC} nuevos apagados inseguros"
                    echo -e "    ${WHITE}→${NC} Recuerda expulsar el disco antes de desconectar\n"
                    alerts=$((alerts + 1))
                fi
            fi

            # Verificar tendencia de temperatura
            local temps=$(echo "$disk_data" | cut -d',' -f7 | grep -v '^$')
            if [ -n "$temps" ]; then
                local avg_temp=$(echo "$temps" | awk '{sum+=$1; count++} END {if(count>0) print int(sum/count); else print 0}')
                if [ "$avg_temp" -gt 60 ] 2>/dev/null; then
                    echo -e "  ${YELLOW}⚠${NC} [$disk] La temperatura promedio es elevada (${YELLOW}${avg_temp}°C${NC})"
                    echo -e "    ${WHITE}→${NC} Verifica la ventilacion\n"
                    alerts=$((alerts + 1))
                fi
            fi

            # Verificar desgaste
            local last_wear=$(echo "$last_record" | cut -d',' -f10)
            if [ -n "$last_wear" ] && [ "$last_wear" -gt 50 ] 2>/dev/null; then
                echo -e "  ${YELLOW}⚠${NC} [$disk] El desgaste del disco es ${YELLOW}${last_wear}%${NC}"
                echo -e "    ${WHITE}→${NC} Considera planificar un reemplazo eventual\n"
                alerts=$((alerts + 1))
            fi

            # Verificar si hubo errores
            local last_errors=$(echo "$last_record" | cut -d',' -f14)
            if [ -n "$last_errors" ] && [ "$last_errors" -gt 0 ] 2>/dev/null; then
                echo -e "  ${RED}✗${NC} [$disk] Se detectaron ${RED}$last_errors${NC} errores de integridad"
                echo -e "    ${WHITE}→${NC} ¡Hacer backup inmediatamente!\n"
                alerts=$((alerts + 1))
            fi
        fi
    done

    if [ $alerts -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} No se detectaron problemas o tendencias preocupantes"
        echo -e "    ${WHITE}→${NC} Los discos estan operando normalmente\n"
    fi
}

show_footer() {
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Comandos utiles:                                                     ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}./track-ssd-history.sh${NC}              - Agregar nuevo registro       ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}./view-history.sh --disk=apple${NC}      - Solo disco Apple             ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}./view-history.sh --disk=samsung${NC}    - Solo disco Samsung           ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}║${NC}  ${WHITE}cat logs/ssd-history.csv${NC}            - Ver archivo CSV completo     ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

show_header
show_overview
show_recent_records
show_temperature_graph
show_statistics
show_alerts
show_footer
