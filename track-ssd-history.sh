#!/bin/bash

# =============================================================================
# Script de Seguimiento Historico para SSDs
# =============================================================================
# Soporta: APPLE (interno) y SAMSUNG (externo)
# Uso: ./track-ssd-history.sh [--disk=apple|samsung]
# =============================================================================

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuracion
source "$SCRIPT_DIR/config.sh"

# -----------------------------------------------------------------------------
# Parsear argumentos
# -----------------------------------------------------------------------------
for arg in "$@"; do
    parse_disk_arg "$arg"
done

# Si no se especifico disco, usar Samsung por defecto (retrocompatibilidad)
if [ ${#SELECTED_DISKS[@]} -eq 0 ]; then
    if check_disk_available "$DISK_SAMSUNG_DEVICE"; then
        SELECTED_DISKS=("SAMSUNG")
        set_disk_samsung
    elif check_disk_available "$DISK_APPLE_DEVICE"; then
        SELECTED_DISKS=("APPLE")
        set_disk_apple
    else
        echo -e "${RED}No hay discos disponibles${NC}"
        exit 1
    fi
fi

# Crear directorio de logs si no existe
ensure_directories

# -----------------------------------------------------------------------------
# Verificar y crear archivo CSV con headers si no existe
# -----------------------------------------------------------------------------
check_csv_headers() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "disk_name,timestamp,date,power_on_hours,power_cycles,unsafe_shutdowns,temperature,temp_sensor1,temp_sensor2,percentage_used,available_spare,data_written_gb,data_read_gb,media_errors,error_log_entries,smart_status" > "$LOG_FILE"
        echo -e "${GREEN}✓${NC} Archivo de historico creado: $LOG_FILE"
    else
        # Verificar si el CSV tiene el nuevo formato (con disk_name)
        local first_column=$(head -1 "$LOG_FILE" | cut -d',' -f1)
        if [ "$first_column" != "disk_name" ]; then
            echo -e "${YELLOW}⚠${NC} Migrando CSV a nuevo formato..."
            migrate_csv
        fi
    fi
}

# -----------------------------------------------------------------------------
# Migrar CSV antiguo al nuevo formato
# -----------------------------------------------------------------------------
migrate_csv() {
    local temp_file="${LOG_FILE}.tmp"

    # Crear nuevo header
    echo "disk_name,timestamp,date,power_on_hours,power_cycles,unsafe_shutdowns,temperature,temp_sensor1,temp_sensor2,percentage_used,available_spare,data_written_gb,data_read_gb,media_errors,error_log_entries,smart_status" > "$temp_file"

    # Migrar datos existentes (asumiendo que eran del Samsung)
    tail -n +2 "$LOG_FILE" | while IFS= read -r line; do
        echo "SAMSUNG,$line" >> "$temp_file"
    done

    # Reemplazar archivo original
    mv "$temp_file" "$LOG_FILE"
    echo -e "${GREEN}✓${NC} CSV migrado exitosamente"
}

# -----------------------------------------------------------------------------
# Funcion para registrar metricas de un disco
# -----------------------------------------------------------------------------
record_disk_metrics() {
    local disk_name="$1"
    set_disk_by_name "$disk_name"

    # Verificar que el disco existe
    if ! check_disk_available "$CURRENT_DISK_DEVICE"; then
        echo -e "${RED}✗ Disco $CURRENT_DISK_NAME no detectado${NC}"
        return 1
    fi

    # Obtener datos SMART
    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE" 2>/dev/null)

    # Extraer valores
    local timestamp=$(date +%s)
    local date_str=$(date '+%Y-%m-%d %H:%M:%S')
    local power_on_hours=$(echo "$smart_data" | grep "Power On Hours:" | awk '{print $4}')
    local power_cycles=$(echo "$smart_data" | grep "Power Cycles:" | awk '{print $3}')
    local unsafe_shutdowns=$(echo "$smart_data" | grep "Unsafe Shutdowns:" | awk '{print $3}')
    local temperature=$(echo "$smart_data" | grep "^Temperature:" | awk '{print $2}')
    local temp_sensor1=$(echo "$smart_data" | grep "Temperature Sensor 1:" | awk '{print $4}')
    local temp_sensor2=$(echo "$smart_data" | grep "Temperature Sensor 2:" | awk '{print $4}')
    local percentage_used=$(echo "$smart_data" | grep "Percentage Used:" | awk '{print $3}' | tr -d '%')
    local available_spare=$(echo "$smart_data" | grep "Available Spare:" | awk '{print $3}' | tr -d '%')
    local data_written=$(echo "$smart_data" | grep "Data Units Written:" | grep -o '\[[0-9.]* [GMT]B\]' | tr -d '[]' | awk '{print $1}')
    local data_read=$(echo "$smart_data" | grep "Data Units Read:" | grep -o '\[[0-9.]* [GMT]B\]' | tr -d '[]' | awk '{print $1}')
    local media_errors=$(echo "$smart_data" | grep "Media and Data Integrity Errors:" | awk '{print $6}')
    local error_log_entries=$(echo "$smart_data" | grep "Error Information Log Entries:" | awk '{print $5}')
    local smart_status=$(echo "$smart_data" | grep "SMART overall-health" | cut -d: -f2 | xargs)

    # Valores por defecto para campos vacios
    [ -z "$power_on_hours" ] && power_on_hours=""
    [ -z "$power_cycles" ] && power_cycles=""
    [ -z "$unsafe_shutdowns" ] && unsafe_shutdowns=""
    [ -z "$temperature" ] && temperature=""
    [ -z "$temp_sensor1" ] && temp_sensor1=""
    [ -z "$temp_sensor2" ] && temp_sensor2=""
    [ -z "$percentage_used" ] && percentage_used=""
    [ -z "$available_spare" ] && available_spare=""
    [ -z "$data_written" ] && data_written=""
    [ -z "$data_read" ] && data_read=""
    [ -z "$media_errors" ] && media_errors="0"
    [ -z "$error_log_entries" ] && error_log_entries="0"

    # Agregar registro al CSV
    echo "$CURRENT_DISK_NAME,$timestamp,$date_str,$power_on_hours,$power_cycles,$unsafe_shutdowns,$temperature,$temp_sensor1,$temp_sensor2,$percentage_used,$available_spare,$data_written,$data_read,$media_errors,$error_log_entries,$smart_status" >> "$LOG_FILE"

    # Mostrar informacion del registro
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${WHITE}Registro de Metricas - $CURRENT_DISK_NAME${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -e "Fecha: ${WHITE}$date_str${NC}"
    [ -n "$temperature" ] && echo -e "Temperatura: ${WHITE}${temperature}°C${NC}"
    [ -n "$percentage_used" ] && echo -e "Desgaste: ${WHITE}${percentage_used}%${NC}"
    [ -n "$power_on_hours" ] && echo -e "Horas encendido: ${WHITE}${power_on_hours}h${NC}"
    [ -n "$unsafe_shutdowns" ] && echo -e "Apagados inseguros: ${WHITE}$unsafe_shutdowns${NC}"
    echo -e "Estado SMART: ${WHITE}$smart_status${NC}"

    echo -e "\n${GREEN}✓${NC} Registro guardado en: ${WHITE}$LOG_FILE${NC}"

    # Mostrar estadisticas si hay multiples registros para este disco
    show_disk_statistics "$disk_name"
}

# -----------------------------------------------------------------------------
# Mostrar estadisticas historicas de un disco
# -----------------------------------------------------------------------------
show_disk_statistics() {
    local disk_name="$1"

    # Contar registros de este disco
    local record_count=$(grep "^$disk_name," "$LOG_FILE" | wc -l | xargs)

    if [ "$record_count" -gt 1 ]; then
        echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}Estadisticas Historicas $disk_name (${record_count} registros)${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

        # Obtener primer y ultimo registro de este disco
        local first_record=$(grep "^$disk_name," "$LOG_FILE" | head -1)
        local last_record=$(grep "^$disk_name," "$LOG_FILE" | tail -1)

        local first_date=$(echo "$first_record" | cut -d',' -f3)
        local first_hours=$(echo "$first_record" | cut -d',' -f4)
        local first_unsafe=$(echo "$first_record" | cut -d',' -f6)
        local first_wear=$(echo "$first_record" | cut -d',' -f10)

        local last_date=$(echo "$last_record" | cut -d',' -f3)
        local last_hours=$(echo "$last_record" | cut -d',' -f4)
        local last_unsafe=$(echo "$last_record" | cut -d',' -f6)
        local last_wear=$(echo "$last_record" | cut -d',' -f10)

        echo -e "Primer registro: ${WHITE}$first_date${NC}"
        echo -e "Ultimo registro: ${WHITE}$last_date${NC}"

        # Calculos de cambios (solo si hay valores validos)
        if [ -n "$first_hours" ] && [ -n "$last_hours" ]; then
            local hours_diff=$((last_hours - first_hours))
            echo -e "\n${BOLD}Cambios desde el primer registro:${NC}"
            echo -e "  Horas de uso: ${WHITE}+${hours_diff}h${NC}"
        fi

        if [ -n "$first_unsafe" ] && [ -n "$last_unsafe" ]; then
            local unsafe_diff=$((last_unsafe - first_unsafe))
            echo -e "  Nuevos apagados inseguros: ${WHITE}+${unsafe_diff}${NC}"
        fi

        if [ -n "$first_wear" ] && [ -n "$last_wear" ]; then
            local wear_diff=$(echo "$last_wear - $first_wear" | bc 2>/dev/null || echo "0")
            echo -e "  Incremento de desgaste: ${WHITE}+${wear_diff}%${NC}"
        fi

        # Temperatura promedio
        local temps=$(grep "^$disk_name," "$LOG_FILE" | cut -d',' -f7 | grep -v '^$')
        if [ -n "$temps" ]; then
            local avg_temp=$(echo "$temps" | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "N/A"}')
            local max_temp=$(echo "$temps" | sort -n | tail -1)
            local min_temp=$(echo "$temps" | sort -n | head -1)
            local current_temp=$(echo "$last_record" | cut -d',' -f7)

            echo -e "\n${BOLD}Temperaturas:${NC}"
            [ -n "$current_temp" ] && echo -e "  Actual: ${WHITE}${current_temp}°C${NC}"
            echo -e "  Promedio historico: ${WHITE}${avg_temp}°C${NC}"
            echo -e "  Maxima registrada: ${WHITE}${max_temp}°C${NC}"
            echo -e "  Minima registrada: ${WHITE}${min_temp}°C${NC}"
        fi

        # Advertencias
        if [ -n "$first_unsafe" ] && [ -n "$last_unsafe" ]; then
            local unsafe_diff=$((last_unsafe - first_unsafe))
            if [ "$unsafe_diff" -gt 10 ]; then
                echo -e "\n${YELLOW}⚠ Advertencia:${NC} Se detectaron $unsafe_diff nuevos apagados inseguros."
                echo -e "  Recuerda expulsar el disco antes de desconectarlo."
            fi
        fi

        if [ -n "$first_wear" ] && [ -n "$last_wear" ]; then
            local wear_diff=$(echo "$last_wear - $first_wear" | bc 2>/dev/null || echo "0")
            if (( $(echo "$wear_diff > 5" | bc -l 2>/dev/null || echo "0") )); then
                echo -e "\n${YELLOW}⚠ Advertencia:${NC} El desgaste aumento ${wear_diff}% desde el primer registro."
            fi
        fi
    fi

    # Total de registros en el archivo
    local total_records=$(tail -n +2 "$LOG_FILE" | wc -l | xargs)
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total de registros ($disk_name): ${WHITE}$record_count${NC}"
    echo -e "Total de registros (todos): ${WHITE}$total_records${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# Verificar/crear CSV
check_csv_headers

# Registrar metricas para cada disco seleccionado
for disk in "${SELECTED_DISKS[@]}"; do
    record_disk_metrics "$disk"
done
