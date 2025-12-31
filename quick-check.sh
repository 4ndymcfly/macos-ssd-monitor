#!/bin/bash

# =============================================================================
# Script de Verificacion Rapida para SSDs
# =============================================================================
# Soporta: APPLE (interno) y SAMSUNG (externo)
# Uso: ./quick-check.sh [--disk=apple|samsung]
# =============================================================================

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuracion
source "$SCRIPT_DIR/config.sh"

# -----------------------------------------------------------------------------
# Parsear argumentos
# -----------------------------------------------------------------------------
DISK_ARG=""
for arg in "$@"; do
    if parse_disk_arg "$arg"; then
        DISK_ARG="$arg"
    fi
done

# Si no se especifico disco, usar el primero disponible o pedir seleccion
if [ ${#SELECTED_DISKS[@]} -eq 0 ]; then
    # Modo interactivo si se ejecuta directamente
    if [ -t 0 ]; then
        # Intentar Samsung primero (retrocompatibilidad)
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
fi

# -----------------------------------------------------------------------------
# Funcion principal de verificacion
# -----------------------------------------------------------------------------
run_quick_check() {
    local disk_name="$1"
    set_disk_by_name "$disk_name"

    # Verificar disco
    if ! check_disk_available "$CURRENT_DISK_DEVICE"; then
        echo -e "${RED}✗ Disco $CURRENT_DISK_NAME no detectado${NC}"
        return 1
    fi

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${WHITE}  Quick Check - $CURRENT_DISK_NAME${NC}"
    echo -e "${CYAN}  $CURRENT_DISK_DESC${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Obtener datos SMART
    smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE" 2>/dev/null)

    # Extraer valores clave
    overall_health=$(echo "$smart_data" | grep "SMART overall-health" | cut -d: -f2 | xargs)
    temp=$(echo "$smart_data" | grep "^Temperature:" | awk '{print $2}')
    temp_sensor1=$(echo "$smart_data" | grep "Temperature Sensor 1:" | awk '{print $4}')
    temp_sensor2=$(echo "$smart_data" | grep "Temperature Sensor 2:" | awk '{print $4}')
    spare=$(echo "$smart_data" | grep "Available Spare:" | awk '{print $3}')
    wear=$(echo "$smart_data" | grep "Percentage Used:" | awk '{print $3}')
    errors=$(echo "$smart_data" | grep "Media and Data Integrity Errors:" | awk '{print $6}')
    unsafe=$(echo "$smart_data" | grep "Unsafe Shutdowns:" | awk '{print $3}')
    power_on=$(echo "$smart_data" | grep "Power On Hours:" | awk '{print $4}')
    data_written=$(echo "$smart_data" | grep "Data Units Written:" | grep -o '\[.*\]' | tr -d '[]')

    # Valores por defecto si no se encuentran
    [ -z "$temp" ] && temp="N/A"
    [ -z "$temp_sensor1" ] && temp_sensor1="N/A"
    [ -z "$temp_sensor2" ] && temp_sensor2="N/A"
    [ -z "$spare" ] && spare="N/A"
    [ -z "$wear" ] && wear="N/A"
    [ -z "$errors" ] && errors="0"
    [ -z "$unsafe" ] && unsafe="N/A"
    [ -z "$power_on" ] && power_on="N/A"
    [ -z "$data_written" ] && data_written="N/A"

    # Mostrar informacion
    echo -e "${BOLD}Estado General:${NC}"
    if [ "$overall_health" = "PASSED" ]; then
        echo -e "  ${GREEN}✓${NC} SMART: ${GREEN}$overall_health${NC}"
    else
        echo -e "  ${RED}✗${NC} SMART: ${RED}$overall_health${NC}"
    fi

    echo -e "\n${BOLD}Salud del Disco:${NC}"
    echo -e "  Desgaste: ${WHITE}$wear${NC} | Reserva: ${WHITE}$spare${NC} | Errores: ${WHITE}$errors${NC}"

    echo -e "\n${BOLD}Temperaturas:${NC}"
    if [ "$temp" != "N/A" ]; then
        if [ "$temp" -lt 50 ] 2>/dev/null; then
            color=$GREEN
        elif [ "$temp" -lt 70 ] 2>/dev/null; then
            color=$YELLOW
        else
            color=$RED
        fi
        echo -e "  Actual: ${color}${temp}°C${NC} | Sensor 1: ${WHITE}${temp_sensor1}°C${NC} | Sensor 2: ${WHITE}${temp_sensor2}°C${NC}"
    else
        echo -e "  ${YELLOW}No disponible${NC}"
    fi

    echo -e "\n${BOLD}Uso:${NC}"
    echo -e "  Horas encendido: ${WHITE}${power_on}h${NC} | Apagados inseguros: ${WHITE}$unsafe${NC}"
    echo -e "  Datos escritos: ${WHITE}$data_written${NC}"

    # Estado TRIM - Detectar por BSD Name del disco
    local trim_status=$(system_profiler SPNVMeDataType 2>/dev/null | grep -B 20 "BSD Name: $CURRENT_DISK_DEVICE$" | grep "TRIM Support:" | cut -d: -f2 | xargs)

    if [ -n "$trim_status" ]; then
        if [ "$trim_status" = "Yes" ]; then
            echo -e "\n${BOLD}TRIM:${NC} ${GREEN}✓ Activado${NC}"
        else
            echo -e "\n${BOLD}TRIM:${NC} ${YELLOW}$trim_status${NC}"
        fi
    fi

    # Espacio en disco
    if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
        # Para APFS del sistema, obtener info real del contenedor
        local apfs_container=$(diskutil info / 2>/dev/null | grep "APFS Container:" | awk '{print $3}')
        if [ -n "$apfs_container" ]; then
            local apfs_info=$(diskutil apfs list "$apfs_container" 2>/dev/null)
            local total_bytes=$(echo "$apfs_info" | grep "Capacity Ceiling" | grep -o '[0-9]*' | head -1)
            local used_bytes=$(echo "$apfs_info" | grep "Capacity In Use" | grep -o '[0-9]*' | head -1)
            local free_bytes=$(echo "$apfs_info" | grep "Capacity Not Allocated" | grep -o '[0-9]*' | head -1)
            local used_percent=$(echo "$apfs_info" | grep "Capacity In Use" | grep -o '[0-9.]*%' | head -1)

            # Convertir a GB
            local total_gb=$(echo "scale=0; $total_bytes / 1000000000" | bc 2>/dev/null)
            local used_gb=$(echo "scale=0; $used_bytes / 1000000000" | bc 2>/dev/null)
            local free_gb=$(echo "scale=0; $free_bytes / 1000000000" | bc 2>/dev/null)

            echo -e "\n${BOLD}Espacio (APFS):${NC} Total: ${WHITE}${total_gb}G${NC} | Usado: ${WHITE}${used_gb}G${NC} | Libre: ${WHITE}${free_gb}G${NC} | ${WHITE}${used_percent}${NC}"
        fi
    elif [ -n "$CURRENT_DISK_VOLUME" ] && [ -d "$CURRENT_DISK_VOLUME" ]; then
        df_output=$(df -H "$CURRENT_DISK_VOLUME" | tail -1)
        used=$(echo "$df_output" | awk '{print $3}')
        available=$(echo "$df_output" | awk '{print $4}')
        percent=$(echo "$df_output" | awk '{print $5}')
        echo -e "\n${BOLD}Espacio:${NC} Usado: ${WHITE}$used${NC} | Disponible: ${WHITE}$available${NC} | ${WHITE}$percent${NC}"
    fi

    # Puntuacion rapida
    health_score=100
    [ "$overall_health" != "PASSED" ] && health_score=$((health_score - 50))

    # Extraer numero de wear para comparacion
    wear_num=$(echo "$wear" | tr -d '%')
    if [ -n "$wear_num" ] && [ "$wear_num" -gt 50 ] 2>/dev/null; then
        health_score=$((health_score - 30))
    fi

    if [ "$temp" != "N/A" ] && [ "$temp" -gt 70 ] 2>/dev/null; then
        health_score=$((health_score - 20))
    fi

    if [ "$errors" -gt 0 ] 2>/dev/null; then
        health_score=$((health_score - 40))
    fi

    echo ""
    if [ $health_score -ge 90 ]; then
        echo -e "${BOLD}Puntuacion:${NC} ${GREEN}${BOLD}$health_score/100 - EXCELENTE ✓${NC}"
    elif [ $health_score -ge 70 ]; then
        echo -e "${BOLD}Puntuacion:${NC} ${YELLOW}${BOLD}$health_score/100 - BUENO${NC}"
    else
        echo -e "${BOLD}Puntuacion:${NC} ${RED}${BOLD}$health_score/100 - ATENCION REQUERIDA${NC}"
    fi

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Para analisis completo: ${WHITE}./check-datos-ssd.sh --disk=$disk_name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# -----------------------------------------------------------------------------
# Ejecutar para cada disco seleccionado
# -----------------------------------------------------------------------------
for disk in "${SELECTED_DISKS[@]}"; do
    run_quick_check "$disk"
done
