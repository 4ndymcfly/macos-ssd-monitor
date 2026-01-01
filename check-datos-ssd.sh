#!/bin/bash

# =============================================================================
# Script de Monitoreo Completo para SSDs
# =============================================================================
# Soporta: APPLE (interno) y SAMSUNG (externo)
# Uso: ./check-datos-ssd.sh [--disk=apple|samsung] [--speed-test]
# =============================================================================

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuracion
source "$SCRIPT_DIR/config.sh"

# Configuracion del test de velocidad
SPEED_TEST_SIZE_MB=1024  # 1GB

# -----------------------------------------------------------------------------
# Parsear argumentos
# -----------------------------------------------------------------------------
RUN_SPEED_TEST=false

for arg in "$@"; do
    if parse_disk_arg "$arg"; then
        continue
    elif [ "$arg" = "--speed-test" ] || [ "$arg" = "-s" ]; then
        RUN_SPEED_TEST=true
    fi
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

# -----------------------------------------------------------------------------
# Nota: sudo purge debe estar en sudoers sin password para mejor experiencia
# Añadir con: echo "USER ALL=(ALL) NOPASSWD: /usr/sbin/purge" | sudo tee /etc/sudoers.d/purge-nopasswd
# -----------------------------------------------------------------------------

# =============================================================================
# Funciones de Utilidad
# =============================================================================

print_header() {
    echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  $1${CYAN}${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_section() {
    echo -e "\n${BOLD}${BLUE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "  ${CYAN}•${NC} $1: ${WHITE}$2${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1: ${GREEN}$2${NC}"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1: ${YELLOW}$2${NC}"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1: ${RED}$2${NC}"
}

# =============================================================================
# Funciones de Verificacion
# =============================================================================

check_requirements() {
    print_header "VERIFICACION DE SISTEMA"

    # Verificar que el disco existe
    if ! diskutil info "$CURRENT_DISK_DEVICE" &>/dev/null; then
        print_error "Disco" "El disco $CURRENT_DISK_DEVICE no esta conectado"
        exit 1
    fi
    print_ok "Disco detectado" "$CURRENT_DISK_DEVICE ($CURRENT_DISK_NAME)"

    # Verificar que smartctl esta disponible
    if ! command -v smartctl &>/dev/null; then
        print_error "smartctl" "No esta instalado. Instalar con: brew install smartmontools"
        exit 1
    fi
    print_ok "smartctl" "Disponible"

    # Verificar volumen montado (para speed test)
    if [ -n "$CURRENT_DISK_VOLUME" ] && [ -d "$CURRENT_DISK_VOLUME" ]; then
        print_ok "Volumen montado" "$CURRENT_DISK_VOLUME"
    elif [ -d "$CURRENT_SPEED_TEST_PATH" ]; then
        print_ok "Path de test" "$CURRENT_SPEED_TEST_PATH"
    else
        print_warning "Volumen" "No montado (speed test puede no funcionar)"
    fi
}

show_disk_info() {
    print_header "INFORMACION GENERAL DEL DISCO"

    local info=$(diskutil info "$CURRENT_DISK_DEVICE")

    local device_name=$(echo "$info" | grep "Device / Media Name:" | cut -d: -f2 | xargs)
    local disk_size=$(echo "$info" | grep "Disk Size:" | cut -d: -f2 | cut -d'(' -f1 | xargs)
    local protocol=$(echo "$info" | grep "Protocol:" | cut -d: -f2 | xargs)
    local smart_status=$(echo "$info" | grep "SMART Status:" | cut -d: -f2 | xargs)

    print_info "Tipo" "$CURRENT_DISK_NAME - $CURRENT_DISK_DESC"
    print_info "Dispositivo" "$device_name"
    print_info "Tamaño" "$disk_size"
    print_info "Protocolo" "$protocol"

    if [ "$smart_status" = "Verified" ]; then
        print_ok "Estado SMART" "$smart_status"
    else
        print_error "Estado SMART" "$smart_status"
    fi
}

show_smart_health() {
    print_header "ESTADO DE SALUD SMART"

    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE")

    local overall_health=$(echo "$smart_data" | grep "SMART overall-health" | cut -d: -f2 | xargs)
    if [ "$overall_health" = "PASSED" ]; then
        print_ok "Estado General" "$overall_health"
    else
        print_error "Estado General" "$overall_health"
    fi

    local critical_warning=$(echo "$smart_data" | grep "Critical Warning:" | awk '{print $3}')
    if [ "$critical_warning" = "0x00" ]; then
        print_ok "Advertencias Criticas" "Ninguna ($critical_warning)"
    else
        print_error "Advertencias Criticas" "$critical_warning"
    fi

    local spare=$(echo "$smart_data" | grep "Available Spare:" | awk '{print $3}' | tr -d '%')
    if [ -n "$spare" ]; then
        if [ "$spare" -ge 90 ] 2>/dev/null; then
            print_ok "Capacidad de Reserva" "${spare}%"
        elif [ "$spare" -ge 50 ] 2>/dev/null; then
            print_warning "Capacidad de Reserva" "${spare}%"
        else
            print_error "Capacidad de Reserva" "${spare}%"
        fi
    fi

    local spare_threshold=$(echo "$smart_data" | grep "Available Spare Threshold:" | awk '{print $4}' | tr -d '%')
    [ -n "$spare_threshold" ] && print_info "Umbral de Reserva" "${spare_threshold}%"

    local percentage_used=$(echo "$smart_data" | grep "Percentage Used:" | awk '{print $3}' | tr -d '%')
    if [ -n "$percentage_used" ]; then
        if [ "$percentage_used" -le 10 ] 2>/dev/null; then
            print_ok "Desgaste Total" "${percentage_used}%"
        elif [ "$percentage_used" -le 50 ] 2>/dev/null; then
            print_warning "Desgaste Total" "${percentage_used}%"
        else
            print_error "Desgaste Total" "${percentage_used}%"
        fi
    fi

    local media_errors=$(echo "$smart_data" | grep "Media and Data Integrity Errors:" | awk '{print $6}')
    if [ "$media_errors" = "0" ]; then
        print_ok "Errores de Integridad" "$media_errors"
    else
        print_error "Errores de Integridad" "$media_errors"
    fi

    local error_log=$(echo "$smart_data" | grep "Error Information Log Entries:" | awk '{print $5}')
    if [ "$error_log" = "0" ]; then
        print_ok "Entradas de Error" "$error_log"
    elif [ -n "$error_log" ]; then
        print_error "Entradas de Error" "$error_log"
    fi
}

show_temperatures() {
    print_header "TEMPERATURAS"

    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE")

    local current_temp=$(echo "$smart_data" | grep "^Temperature:" | awk '{print $2}')
    local temp_warning=$(echo "$smart_data" | grep "Warning  Comp. Temp. Threshold:" | awk '{print $5}')
    local temp_critical=$(echo "$smart_data" | grep "Critical Comp. Temp. Threshold:" | awk '{print $5}')

    if [ -n "$current_temp" ]; then
        if [ "$current_temp" -lt 50 ] 2>/dev/null; then
            print_ok "Temperatura Actual" "${current_temp}°C (Excelente)"
        elif [ "$current_temp" -lt 70 ] 2>/dev/null; then
            print_warning "Temperatura Actual" "${current_temp}°C (Normal)"
        else
            print_error "Temperatura Actual" "${current_temp}°C (Alta)"
        fi
    else
        print_info "Temperatura Actual" "No disponible"
    fi

    [ -n "$temp_warning" ] && print_info "Umbral de Advertencia" "${temp_warning}°C"
    [ -n "$temp_critical" ] && print_info "Umbral Critico" "${temp_critical}°C"

    local temp_sensor1=$(echo "$smart_data" | grep "Temperature Sensor 1:" | awk '{print $4}')
    local temp_sensor2=$(echo "$smart_data" | grep "Temperature Sensor 2:" | awk '{print $4}')

    [ -n "$temp_sensor1" ] && print_info "Sensor 1 (Controlador)" "${temp_sensor1}°C"
    [ -n "$temp_sensor2" ] && print_info "Sensor 2 (NAND)" "${temp_sensor2}°C"

    local warning_time=$(echo "$smart_data" | grep "Warning  Comp. Temperature Time:" | awk '{print $5}')
    local critical_time=$(echo "$smart_data" | grep "Critical Comp. Temperature Time:" | awk '{print $5}')

    if [ "$warning_time" = "0" ]; then
        print_ok "Tiempo en Temp. Advertencia" "${warning_time} minutos"
    elif [ -n "$warning_time" ]; then
        print_warning "Tiempo en Temp. Advertencia" "${warning_time} minutos"
    fi

    if [ "$critical_time" = "0" ]; then
        print_ok "Tiempo en Temp. Critica" "${critical_time} minutos"
    elif [ -n "$critical_time" ]; then
        print_error "Tiempo en Temp. Critica" "${critical_time} minutos"
    fi
}

show_usage_stats() {
    print_header "ESTADISTICAS DE USO"

    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE")

    local power_on_hours=$(echo "$smart_data" | grep "Power On Hours:" | awk '{print $4}')
    if [ -n "$power_on_hours" ]; then
        local days=$(echo "scale=1; $power_on_hours/24" | bc)
        print_info "Horas Encendido" "${power_on_hours}h (${days} dias)"
    fi

    local power_cycles=$(echo "$smart_data" | grep "Power Cycles:" | awk '{print $3}')
    [ -n "$power_cycles" ] && print_info "Ciclos de Encendido" "$power_cycles"

    local unsafe_shutdowns=$(echo "$smart_data" | grep "Unsafe Shutdowns:" | awk '{print $3}')
    if [ -n "$unsafe_shutdowns" ]; then
        if [ "$unsafe_shutdowns" -le 5 ] 2>/dev/null; then
            print_ok "Apagados Inseguros" "$unsafe_shutdowns"
        elif [ "$unsafe_shutdowns" -le 20 ] 2>/dev/null; then
            print_warning "Apagados Inseguros" "$unsafe_shutdowns (Revisar expulsion del disco)"
        else
            print_error "Apagados Inseguros" "$unsafe_shutdowns (Demasiados!)"
        fi
    fi

    local data_read=$(echo "$smart_data" | grep "Data Units Read:" | awk '{print $4}' | tr -d ',')
    local gb_read=$(echo "$smart_data" | grep "Data Units Read:" | grep -o '\[.*\]' | tr -d '[]')
    [ -n "$gb_read" ] && print_info "Datos Leidos" "$gb_read"

    local data_written=$(echo "$smart_data" | grep "Data Units Written:" | awk '{print $4}' | tr -d ',')
    local gb_written=$(echo "$smart_data" | grep "Data Units Written:" | grep -o '\[.*\]' | tr -d '[]')
    [ -n "$gb_written" ] && print_info "Datos Escritos" "$gb_written"

    local read_commands=$(echo "$smart_data" | grep "Host Read Commands:" | awk '{print $4}' | tr -d ',.')
    local write_commands=$(echo "$smart_data" | grep "Host Write Commands:" | awk '{print $4}' | tr -d ',.')
    [ -n "$read_commands" ] && print_info "Comandos de Lectura" "$(printf "%'d" $read_commands 2>/dev/null || echo "$read_commands")"
    [ -n "$write_commands" ] && print_info "Comandos de Escritura" "$(printf "%'d" $write_commands 2>/dev/null || echo "$write_commands")"

    local busy_time=$(echo "$smart_data" | grep "Controller Busy Time:" | awk '{print $4}')
    [ -n "$busy_time" ] && print_info "Tiempo Controlador Ocupado" "${busy_time} minutos"
}

show_nvme_info() {
    print_header "INFORMACION NVME"

    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE")

    local model=$(echo "$smart_data" | grep "Model Number:" | cut -d: -f2 | xargs)
    print_info "Modelo" "$model"

    local serial=$(echo "$smart_data" | grep "Serial Number:" | cut -d: -f2 | xargs)
    print_info "Numero de Serie" "$serial"

    local firmware=$(echo "$smart_data" | grep "Firmware Version:" | cut -d: -f2 | xargs)
    print_info "Firmware" "$firmware"

    local nvme_version=$(echo "$smart_data" | grep "NVMe Version:" | cut -d: -f2 | xargs)
    [ -n "$nvme_version" ] && print_info "Version NVMe" "$nvme_version"

    local capacity=$(echo "$smart_data" | grep "Total NVM Capacity:" | grep -o '\[.*\]' | tr -d '[]')
    [ -n "$capacity" ] && print_info "Capacidad Total" "$capacity"
}

show_filesystem_info() {
    print_header "SISTEMA DE ARCHIVOS"

    # Para disco Apple, usar la raiz del sistema
    local mount_path="$CURRENT_DISK_VOLUME"
    if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
        mount_path="/"
    fi

    if [ -z "$mount_path" ] || [ ! -d "$mount_path" ]; then
        print_warning "Volumen" "No montado actualmente"
        return
    fi

    # Tipo de filesystem
    if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
        print_info "Tipo de Sistema" "APFS (Sistema)"
    else
        local volume_info=$(diskutil info "$mount_path" 2>/dev/null)
        local fs_type=$(echo "$volume_info" | grep "Type (Bundle):" | cut -d: -f2 | xargs)
        [ -n "$fs_type" ] && print_info "Tipo de Sistema" "$fs_type"
    fi

    # TRIM Support - Detectar por BSD Name del disco
    local trim_support=$(system_profiler SPNVMeDataType 2>/dev/null | grep -B 20 "BSD Name: $CURRENT_DISK_DEVICE$" | grep "TRIM Support:" | cut -d: -f2 | xargs)
    if [ "$trim_support" = "Yes" ]; then
        print_ok "Soporte TRIM" "Activado"
    elif [ -n "$trim_support" ]; then
        print_warning "Soporte TRIM" "$trim_support"
    else
        print_info "Soporte TRIM" "No detectado"
    fi

    # Espacio en disco
    local total_space used_space available_space usage_percent

    if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
        # Para APFS del sistema, obtener info real del contenedor
        local apfs_container=$(diskutil info / 2>/dev/null | grep "APFS Container:" | awk '{print $3}')
        if [ -n "$apfs_container" ]; then
            local apfs_info=$(diskutil apfs list "$apfs_container" 2>/dev/null)
            local total_bytes=$(echo "$apfs_info" | grep "Capacity Ceiling" | grep -o '[0-9]*' | head -1)
            local used_bytes=$(echo "$apfs_info" | grep "Capacity In Use" | grep -o '[0-9]*' | head -1)
            local free_bytes=$(echo "$apfs_info" | grep "Capacity Not Allocated" | grep -o '[0-9]*' | head -1)
            # Extraer porcentaje específicamente (ej: "50.2% used" -> "50")
            usage_percent=$(echo "$apfs_info" | grep "Capacity In Use" | grep -o '([0-9.]*%' | tr -d '(%' | cut -d'.' -f1)

            total_space="$(echo "scale=0; $total_bytes / 1000000000" | bc) GB"
            used_space="$(echo "scale=0; $used_bytes / 1000000000" | bc) GB"
            available_space="$(echo "scale=0; $free_bytes / 1000000000" | bc) GB"
        fi
    else
        local df_output=$(df -H "$mount_path" | tail -1)
        total_space=$(echo "$df_output" | awk '{print $2}')
        used_space=$(echo "$df_output" | awk '{print $3}')
        available_space=$(echo "$df_output" | awk '{print $4}')
        usage_percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    fi

    print_info "Espacio Total" "$total_space"
    print_info "Espacio Usado" "$used_space"
    print_info "Espacio Disponible" "$available_space"

    if [ "$usage_percent" -lt 80 ] 2>/dev/null; then
        print_ok "Uso del Disco" "${usage_percent}%"
    elif [ "$usage_percent" -lt 90 ] 2>/dev/null; then
        print_warning "Uso del Disco" "${usage_percent}%"
    else
        print_error "Uso del Disco" "${usage_percent}% (Casi lleno!)"
    fi
}

run_speed_test() {
    print_header "TEST DE VELOCIDAD"

    local test_path="$CURRENT_SPEED_TEST_PATH"
    local test_file="${test_path}/.speedtest_tmp_file_$$"

    if [ ! -d "$test_path" ]; then
        print_error "Test" "El path $test_path no existe"
        return 1
    fi

    # Verificar permisos de escritura
    if [ ! -w "$test_path" ]; then
        print_error "Test" "Sin permisos de escritura en $test_path"
        return 1
    fi

    echo -e "${CYAN}Ejecutando test de velocidad con archivo de ${SPEED_TEST_SIZE_MB}MB...${NC}"
    echo -e "${CYAN}Path: $test_path${NC}\n"

    # Test de Escritura
    echo -e "${YELLOW}Probando velocidad de ESCRITURA...${NC}"
    local write_start=$(date +%s.%N)
    dd if=/dev/zero of="$test_file" bs=1m count=$SPEED_TEST_SIZE_MB 2>&1 | grep -v records
    sync
    local write_end=$(date +%s.%N)
    local write_time=$(echo "$write_end - $write_start" | bc)
    local write_speed=$(echo "scale=2; ($SPEED_TEST_SIZE_MB / $write_time)" | bc)

    print_ok "Velocidad de Escritura" "${write_speed} MB/s (${write_time}s)"

    # Limpiar cache del sistema para lectura real (no desde cache)
    echo -e "${CYAN}Limpiando cache del sistema...${NC}"
    sudo purge 2>/dev/null || echo -e "${YELLOW}(Cache no limpiada - lectura puede ser desde cache)${NC}"
    sleep 2

    # Test de Lectura
    echo -e "\n${YELLOW}Probando velocidad de LECTURA...${NC}"
    local read_start=$(date +%s.%N)
    dd if="$test_file" of=/dev/null bs=1m 2>&1 | grep -v records
    local read_end=$(date +%s.%N)
    local read_time=$(echo "$read_end - $read_start" | bc)
    local read_speed=$(echo "scale=2; ($SPEED_TEST_SIZE_MB / $read_time)" | bc)

    print_ok "Velocidad de Lectura" "${read_speed} MB/s (${read_time}s)"

    # Limpiar archivo temporal
    rm -f "$test_file"
    print_ok "Limpieza" "Archivo temporal eliminado"

    # Evaluacion segun tipo de disco
    echo ""
    local expected_speed=3000
    if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
        expected_speed=2000  # El disco interno tiene diferentes expectativas
    fi

    if (( $(echo "$write_speed > $expected_speed" | bc -l) )); then
        print_ok "Evaluacion Escritura" "Excelente rendimiento"
    elif (( $(echo "$write_speed > 1500" | bc -l) )); then
        print_warning "Evaluacion Escritura" "Buen rendimiento"
    else
        print_error "Evaluacion Escritura" "Rendimiento bajo, revisar conexion"
    fi

    if (( $(echo "$read_speed > $expected_speed" | bc -l) )); then
        print_ok "Evaluacion Lectura" "Excelente rendimiento"
    elif (( $(echo "$read_speed > 1500" | bc -l) )); then
        print_warning "Evaluacion Lectura" "Buen rendimiento"
    else
        print_error "Evaluacion Lectura" "Rendimiento bajo, revisar conexion"
    fi
}

show_summary() {
    print_header "RESUMEN EJECUTIVO - $CURRENT_DISK_NAME"

    local smart_data=$(smartctl -a "$CURRENT_DISK_DEVICE")

    local overall_health=$(echo "$smart_data" | grep "SMART overall-health" | cut -d: -f2 | xargs)
    local percentage_used=$(echo "$smart_data" | grep "Percentage Used:" | awk '{print $3}' | tr -d '%')
    local current_temp=$(echo "$smart_data" | grep "^Temperature:" | awk '{print $2}')
    local media_errors=$(echo "$smart_data" | grep "Media and Data Integrity Errors:" | awk '{print $6}')
    local unsafe_shutdowns=$(echo "$smart_data" | grep "Unsafe Shutdowns:" | awk '{print $3}')
    local spare=$(echo "$smart_data" | grep "Available Spare:" | awk '{print $3}' | tr -d '%')

    # Valores por defecto
    [ -z "$percentage_used" ] && percentage_used=0
    [ -z "$current_temp" ] && current_temp=0
    [ -z "$media_errors" ] && media_errors=0
    [ -z "$spare" ] && spare=100

    # Calcular puntuacion de salud
    local health_score=100

    if [ "$overall_health" != "PASSED" ]; then
        health_score=$((health_score - 50))
    fi

    if [ "$percentage_used" -gt 80 ] 2>/dev/null; then
        health_score=$((health_score - 30))
    elif [ "$percentage_used" -gt 50 ] 2>/dev/null; then
        health_score=$((health_score - 15))
    elif [ "$percentage_used" -gt 20 ] 2>/dev/null; then
        health_score=$((health_score - 5))
    fi

    if [ "$current_temp" -gt 70 ] 2>/dev/null; then
        health_score=$((health_score - 20))
    elif [ "$current_temp" -gt 60 ] 2>/dev/null; then
        health_score=$((health_score - 10))
    fi

    if [ "$media_errors" -gt 0 ] 2>/dev/null; then
        health_score=$((health_score - 40))
    fi

    if [ "$spare" -lt 50 ] 2>/dev/null; then
        health_score=$((health_score - 30))
    elif [ "$spare" -lt 90 ] 2>/dev/null; then
        health_score=$((health_score - 10))
    fi

    # Mostrar puntuacion
    echo -e "${BOLD}Puntuacion de Salud del Disco:${NC}"
    if [ $health_score -ge 90 ]; then
        echo -e "${GREEN}${BOLD}  ████████████████████  ${health_score}/100 - EXCELENTE${NC}"
    elif [ $health_score -ge 70 ]; then
        echo -e "${YELLOW}${BOLD}  ███████████████      ${health_score}/100 - BUENO${NC}"
    elif [ $health_score -ge 50 ]; then
        echo -e "${YELLOW}${BOLD}  ██████████           ${health_score}/100 - REGULAR${NC}"
    else
        echo -e "${RED}${BOLD}  █████                ${health_score}/100 - CRITICO${NC}"
    fi

    echo ""
    print_info "Estado SMART" "$overall_health"
    print_info "Desgaste" "${percentage_used}%"
    [ "$current_temp" != "0" ] && print_info "Temperatura" "${current_temp}°C"
    print_info "Errores de Medios" "$media_errors"
    [ "$spare" != "100" ] && print_info "Capacidad de Reserva" "${spare}%"

    # Recomendaciones
    echo ""
    echo -e "${BOLD}${MAGENTA}Recomendaciones:${NC}"

    if [ -n "$unsafe_shutdowns" ] && [ "$unsafe_shutdowns" -gt 30 ] 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} Hay $unsafe_shutdowns apagados inseguros. Recuerda expulsar el disco antes de desconectar."
    fi

    if [ "$current_temp" -gt 60 ] 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} Temperatura elevada (${current_temp}°C). Asegurate de buena ventilacion."
    fi

    if [ "$percentage_used" -gt 50 ] 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} Desgaste al ${percentage_used}%. Considera planificar reemplazo."
    fi

    if [ "$media_errors" -gt 0 ] 2>/dev/null; then
        echo -e "  ${RED}✗${NC} Se detectaron $media_errors errores de integridad. ¡Hacer backup inmediatamente!"
    fi

    if [ $health_score -ge 90 ]; then
        echo -e "  ${GREEN}✓${NC} El disco esta en condiciones optimas. Continua con buenas practicas."
    fi
}

# =============================================================================
# Funcion Principal
# =============================================================================

run_full_check() {
    local disk_name="$1"
    set_disk_by_name "$disk_name"

    echo -e "${BOLD}${WHITE}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║       Monitor de Salud - $CURRENT_DISK_NAME"
    echo "║       $CURRENT_DISK_DESC"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}Fecha: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}Sistema: $(sw_vers -productName) $(sw_vers -productVersion)${NC}\n"

    check_requirements
    show_disk_info
    show_nvme_info
    show_smart_health
    show_temperatures
    show_usage_stats
    show_filesystem_info

    # Speed test si se solicita
    if [ "$RUN_SPEED_TEST" = true ]; then
        echo ""
        read -p "$(echo -e ${YELLOW}¿Ejecutar test de velocidad? Esto escribira ${SPEED_TEST_SIZE_MB}MB. [y/N]:${NC} )" -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_speed_test
        fi
    fi

    show_summary

    echo -e "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Analisis completado exitosamente                                     ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# =============================================================================
# Ejecutar
# =============================================================================

for disk in "${SELECTED_DISKS[@]}"; do
    run_full_check "$disk"
done
