#!/bin/bash

# =============================================================================
# Dashboard Interactivo para Monitoreo de SSDs
# =============================================================================
# Soporta: APPLE (interno) y SAMSUNG (externo)
# =============================================================================

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuración
source "$SCRIPT_DIR/config.sh"

# =============================================================================
# Funciones del Dashboard
# =============================================================================

show_header() {
    clear_screen
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                       ║"
    echo "║              Dashboard de Monitoreo SSD                               ║"
    echo "║              Sistema Multi-Disco                                      ║"
    echo "║                                                                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

show_current_selection() {
    echo -e "${BOLD}Disco(s) Seleccionado(s):${NC}"
    for disk in "${SELECTED_DISKS[@]}"; do
        if [ "$disk" = "APPLE" ]; then
            echo -e "  ${GREEN}>${NC} ${WHITE}$DISK_APPLE_NAME${NC} - $DISK_APPLE_DESC"
        elif [ "$disk" = "SAMSUNG" ]; then
            echo -e "  ${GREEN}>${NC} ${WHITE}$DISK_SAMSUNG_NAME${NC} - $DISK_SAMSUNG_DESC"
        fi
    done
    echo ""
}

show_menu() {
    echo -e "${BOLD}Opciones Disponibles:${NC}\n"

    echo -e "  ${GREEN}1${NC}) ${WHITE}Verificacion Rapida${NC} - Resumen del estado actual"
    echo -e "  ${GREEN}2${NC}) ${WHITE}Analisis Completo${NC} - Reporte detallado de salud"
    echo -e "  ${GREEN}3${NC}) ${WHITE}Test de Velocidad${NC} - Benchmark de lectura/escritura"
    echo -e "  ${GREEN}4${NC}) ${WHITE}Registrar Metricas${NC} - Guardar snapshot en historico"
    echo -e "  ${GREEN}5${NC}) ${WHITE}Ver Historico${NC} - Visualizar tendencias y estadisticas"
    echo -e "  ${GREEN}6${NC}) ${WHITE}Solo Temperaturas${NC} - Monitoreo termico"
    echo -e "  ${GREEN}7${NC}) ${WHITE}Exportar Reporte${NC} - Generar reporte en texto"
    echo -e "  ${GREEN}8${NC}) ${WHITE}Informacion del Disco${NC} - Detalles tecnicos (diskutil)"
    echo -e "  ${GREEN}9${NC}) ${WHITE}Expulsar Disco${NC} - Desmontar de forma segura"

    # Opcion solo para disco externo Samsung
    if [[ " ${SELECTED_DISKS[*]} " =~ " SAMSUNG " ]]; then
        echo -e "  ${MAGENTA}m${NC}) ${WHITE}Monitor Desconexion${NC} - Vigilar desconexiones (solo Samsung)"
    fi

    echo -e "  ${YELLOW}c${NC}) ${WHITE}Cambiar Disco${NC} - Seleccionar otro disco"
    echo -e "  ${RED}0${NC}) ${WHITE}Salir${NC}"

    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

pause_screen() {
    echo -e "\n${CYAN}Presiona Enter para continuar...${NC}"
    read
}

# =============================================================================
# Funciones de Opciones
# =============================================================================

run_for_each_disk() {
    local script_name="$1"
    shift
    local extra_args="$@"

    for disk in "${SELECTED_DISKS[@]}"; do
        if [ ${#SELECTED_DISKS[@]} -gt 1 ]; then
            if [ "$disk" = "APPLE" ]; then
                print_disk_separator "$DISK_APPLE_NAME" "$DISK_APPLE_DESC"
            else
                print_disk_separator "$DISK_SAMSUNG_NAME" "$DISK_SAMSUNG_DESC"
            fi
        fi

        cd "$SCRIPT_DIR" && ./"$script_name" --disk="$disk" $extra_args
    done
}

option_1() {
    clear_screen
    run_for_each_disk "quick-check.sh"
    pause_screen
}

option_2() {
    clear_screen
    run_for_each_disk "check-datos-ssd.sh"
    pause_screen
}

option_3() {
    clear_screen
    run_for_each_disk "check-datos-ssd.sh" "--speed-test"
    pause_screen
}

option_4() {
    clear_screen
    run_for_each_disk "track-ssd-history.sh"
    pause_screen
}

option_5() {
    clear_screen
    cd "$SCRIPT_DIR" && ./view-history.sh
    pause_screen
}

option_6() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Monitoreo de Temperatura                                             ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"

    for disk in "${SELECTED_DISKS[@]}"; do
        set_disk_by_name "$disk"

        if [ ${#SELECTED_DISKS[@]} -gt 1 ]; then
            echo -e "${BOLD}${MAGENTA}=== $CURRENT_DISK_NAME ===${NC}\n"
        fi

        if check_disk_available "$CURRENT_DISK_DEVICE"; then
            smartctl -a "$CURRENT_DISK_DEVICE" | grep -E "(^Temperature|Temperature Sensor|Temp\. Threshold|Temperature Time)" | while read line; do
                echo -e "  ${CYAN}•${NC} ${WHITE}$line${NC}"
            done
        else
            echo -e "  ${RED}Disco no disponible${NC}"
        fi
        echo ""
    done

    echo -e "${BOLD}Interpretacion:${NC}"
    echo -e "  ${GREEN}< 50°C${NC} - Excelente"
    echo -e "  ${YELLOW}50-69°C${NC} - Normal"
    echo -e "  ${RED}> 70°C${NC} - Alta (verificar ventilacion)"

    pause_screen
}

option_7() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Exportar Reporte                                                     ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"

    ensure_directories

    for disk in "${SELECTED_DISKS[@]}"; do
        set_disk_by_name "$disk"

        if ! check_disk_available "$CURRENT_DISK_DEVICE"; then
            echo -e "${RED}Disco $CURRENT_DISK_NAME no disponible${NC}"
            continue
        fi

        timestamp=$(date +%Y%m%d_%H%M%S)
        report_file="$REPORTS_DIR/ssd-report-${CURRENT_DISK_NAME}-${timestamp}.txt"

        echo "Generando reporte para $CURRENT_DISK_NAME..."

        {
            echo "═══════════════════════════════════════════════════════════════════════"
            echo "  Reporte de Salud - $CURRENT_DISK_NAME"
            echo "  $CURRENT_DISK_DESC"
            echo "  Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "═══════════════════════════════════════════════════════════════════════"
            echo ""

            echo "▶ SMART STATUS"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            smartctl -H "$CURRENT_DISK_DEVICE"
            echo ""

            echo "▶ INFORMACION COMPLETA"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            smartctl -a "$CURRENT_DISK_DEVICE"
            echo ""

            echo "▶ INFORMACION DEL VOLUMEN"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            diskutil info "$CURRENT_DISK_DEVICE"
            echo ""

            echo "▶ SOPORTE TRIM"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            local trim_status=$(system_profiler SPNVMeDataType 2>/dev/null | grep -B 20 "BSD Name: $CURRENT_DISK_DEVICE$" | grep "TRIM Support:" | cut -d: -f2 | xargs)
            echo "TRIM Support: ${trim_status:-No detectado}"
            echo ""

            if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
                echo "▶ CONTENEDOR APFS"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                local container=$(diskutil info / 2>/dev/null | grep "APFS Container:" | awk '{print $3}')
                if [ -n "$container" ]; then
                    diskutil apfs list "$container"
                fi
                echo ""
            elif [ -n "$CURRENT_DISK_VOLUME" ] && [ -d "$CURRENT_DISK_VOLUME" ]; then
                echo "▶ ESPACIO EN DISCO"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                df -h "$CURRENT_DISK_VOLUME"
                echo ""
            fi

            echo "═══════════════════════════════════════════════════════════════════════"
            echo "  Fin del Reporte"
            echo "═══════════════════════════════════════════════════════════════════════"
        } > "$report_file"

        echo -e "${GREEN}✓${NC} Reporte generado: ${WHITE}$report_file${NC}"
    done

    pause_screen
}

option_8() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Informacion del Disco                                                ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"

    for disk in "${SELECTED_DISKS[@]}"; do
        set_disk_by_name "$disk"

        if [ ${#SELECTED_DISKS[@]} -gt 1 ]; then
            echo -e "${BOLD}${MAGENTA}=== $CURRENT_DISK_NAME ===${NC}\n"
        fi

        if ! check_disk_available "$CURRENT_DISK_DEVICE"; then
            echo -e "${RED}Disco no disponible${NC}"
            continue
        fi

        if [ "$CURRENT_DISK_NAME" = "APPLE" ]; then
            # Para Apple, mostrar info del contenedor APFS
            echo -e "${BOLD}${BLUE}▶ Dispositivo Fisico${NC}\n"
            diskutil info "$CURRENT_DISK_DEVICE"

            echo -e "\n${BOLD}${BLUE}▶ Contenedor APFS${NC}\n"
            local container=$(diskutil info / 2>/dev/null | grep "APFS Container:" | awk '{print $3}')
            if [ -n "$container" ]; then
                diskutil apfs list "$container"
            else
                echo -e "${YELLOW}No se pudo obtener info del contenedor APFS${NC}"
            fi

            echo -e "\n${BOLD}${BLUE}▶ Soporte TRIM${NC}"
            local trim_status=$(system_profiler SPNVMeDataType 2>/dev/null | grep -B 20 "BSD Name: $CURRENT_DISK_DEVICE$" | grep "TRIM Support:" | cut -d: -f2 | xargs)
            echo -e "TRIM: ${WHITE}${trim_status:-No detectado}${NC}"
        else
            # Para Samsung u otros, usar diskutil normal
            diskutil info "$CURRENT_DISK_DEVICE"

            echo -e "\n${BOLD}${BLUE}▶ Soporte TRIM${NC}"
            local trim_status=$(system_profiler SPNVMeDataType 2>/dev/null | grep -B 20 "BSD Name: $CURRENT_DISK_DEVICE$" | grep "TRIM Support:" | cut -d: -f2 | xargs)
            echo -e "TRIM: ${WHITE}${trim_status:-No detectado}${NC}"
        fi
        echo ""
    done

    pause_screen
}

option_9() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Expulsar Disco Seguro                                                ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"

    # Verificar si hay discos que se pueden expulsar
    local can_eject=false

    for disk in "${SELECTED_DISKS[@]}"; do
        if [ "$disk" = "SAMSUNG" ]; then
            can_eject=true
            break
        fi
    done

    if [ "$can_eject" = false ]; then
        echo -e "${YELLOW}⚠ El disco interno APPLE no se puede expulsar.${NC}"
        echo -e "Solo los discos externos pueden ser expulsados.\n"
        pause_screen
        return
    fi

    # Solo expulsar Samsung si está seleccionado
    for disk in "${SELECTED_DISKS[@]}"; do
        if [ "$disk" = "SAMSUNG" ]; then
            echo -e "${YELLOW}⚠ Esto desmontara el volumen $DISK_SAMSUNG_VOLUME${NC}\n"
            read -p "¿Deseas continuar? [y/N]: " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if diskutil unmount "$DISK_SAMSUNG_VOLUME"; then
                    echo -e "\n${GREEN}✓${NC} $DISK_SAMSUNG_NAME expulsado de forma segura"
                    echo -e "Puedes desconectar el disco ahora"
                    echo -e "\n${CYAN}Presiona Enter para salir...${NC}"
                    read
                    exit 0
                else
                    echo -e "\n${RED}✗${NC} Error al expulsar el disco"
                    pause_screen
                fi
            fi
        fi
    done
}

option_change_disk() {
    show_header
    select_disk
}

# Variable global para el PID del monitor
MONITOR_PID=""
MONITOR_LOG_FILE=""

option_monitor() {
    clear_screen
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${WHITE}  Monitor de Desconexion - Samsung 990 Pro                             ${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}\n"

    # Verificar si Samsung está conectado
    if ! check_disk_available "$DISK_SAMSUNG_DEVICE"; then
        echo -e "${RED}✗ El disco Samsung no está conectado${NC}"
        pause_screen
        return
    fi

    # Verificar si ya hay un monitor activo
    if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Ya hay un monitor activo${NC}"
        echo -e "  PID: ${WHITE}$MONITOR_PID${NC}"
        echo -e "  Log: ${WHITE}$MONITOR_LOG_FILE${NC}\n"

        echo -e "${BOLD}Opciones:${NC}"
        echo -e "  ${GREEN}1${NC}) Ver log en tiempo real"
        echo -e "  ${RED}2${NC}) Detener monitor"
        echo -e "  ${YELLOW}3${NC}) Volver al menu\n"

        read -p "$(echo -e ${WHITE}Selecciona [1-3]: ${NC})" subchoice

        case $subchoice in
            1)
                echo -e "\n${CYAN}Mostrando log en tiempo real (Ctrl+C para salir)...${NC}\n"
                tail -f "$MONITOR_LOG_FILE" 2>/dev/null
                ;;
            2)
                kill "$MONITOR_PID" 2>/dev/null
                echo -e "\n${GREEN}✓ Monitor detenido${NC}"
                echo -e "Log guardado en: ${WHITE}$MONITOR_LOG_FILE${NC}"
                MONITOR_PID=""
                pause_screen
                ;;
            3)
                return
                ;;
        esac
        return
    fi

    # Crear archivo de log
    ensure_directories
    local timestamp=$(date +%Y%m%d_%H%M%S)
    MONITOR_LOG_FILE="$LOG_DIR/${timestamp}_log_desconexion.log"

    echo -e "${BOLD}Este monitor vigilará:${NC}"
    echo -e "  ${CYAN}•${NC} Eventos de disco (mount/unmount)"
    echo -e "  ${CYAN}•${NC} Eventos NVMe"
    echo -e "  ${CYAN}•${NC} Eventos Thunderbolt"
    echo -e "  ${CYAN}•${NC} Desconexiones inesperadas\n"

    echo -e "${BOLD}Log se guardará en:${NC}"
    echo -e "  ${WHITE}$MONITOR_LOG_FILE${NC}\n"

    echo -e "${YELLOW}⚠ El monitor se ejecutará en segundo plano.${NC}"
    echo -e "${YELLOW}  Puedes seguir usando el dashboard normalmente.${NC}\n"

    read -p "$(echo -e ${WHITE}¿Iniciar monitor? [S/n]: ${NC})" confirm

    if [[ ! $confirm =~ ^[Nn]$ ]]; then
        # Escribir cabecera del log
        {
            echo "═══════════════════════════════════════════════════════════════════════"
            echo "  Monitor de Desconexión - Samsung 990 Pro"
            echo "  Iniciado: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "  Disco: $DISK_SAMSUNG_DEVICE ($DISK_SAMSUNG_DESC)"
            echo "═══════════════════════════════════════════════════════════════════════"
            echo ""
        } > "$MONITOR_LOG_FILE"

        # Iniciar monitor en segundo plano
        (
            log stream --process kernel --style compact 2>/dev/null | \
            grep --line-buffered -iE "disk|nvme|thunderbolt|terminate|eject|unmount|disconnect|remove" | \
            while read -r line; do
                echo "[$(date '+%H:%M:%S')] $line" >> "$MONITOR_LOG_FILE"

                # Detectar desconexión específica del Samsung
                if echo "$line" | grep -qi "disk4\|990.pro\|terminate"; then
                    echo "[$(date '+%H:%M:%S')] ⚠️  POSIBLE DESCONEXIÓN DETECTADA" >> "$MONITOR_LOG_FILE"
                fi
            done
        ) &

        MONITOR_PID=$!

        echo -e "\n${GREEN}✓ Monitor iniciado${NC}"
        echo -e "  PID: ${WHITE}$MONITOR_PID${NC}"
        echo -e "  Log: ${WHITE}$MONITOR_LOG_FILE${NC}"
        echo -e "\n${CYAN}Vuelve a esta opción (m) para ver el log o detener el monitor.${NC}"
    else
        echo -e "\n${YELLOW}Monitor no iniciado${NC}"
    fi

    pause_screen
}

# =============================================================================
# Main Loop
# =============================================================================

main() {
    # Mostrar cabecera inicial
    show_header

    # Seleccionar disco al inicio
    select_disk

    # Bucle principal del menú
    while true; do
        show_header
        show_current_selection
        show_menu

        # Mostrar 'm' solo si Samsung está seleccionado
        local prompt_opts="0-9, c"
        if [[ " ${SELECTED_DISKS[*]} " =~ " SAMSUNG " ]]; then
            prompt_opts="0-9, c, m"
        fi

        read -p "$(echo -e ${WHITE}Selecciona una opcion [$prompt_opts]: ${NC})" choice

        case $choice in
            1) option_1 ;;
            2) option_2 ;;
            3) option_3 ;;
            4) option_4 ;;
            5) option_5 ;;
            6) option_6 ;;
            7) option_7 ;;
            8) option_8 ;;
            9) option_9 ;;
            m|M)
                # Solo si Samsung está seleccionado
                if [[ " ${SELECTED_DISKS[*]} " =~ " SAMSUNG " ]]; then
                    option_monitor
                else
                    echo -e "\n${RED}Opcion solo disponible para disco Samsung${NC}"
                    sleep 1
                fi
                ;;
            c|C) option_change_disk ;;
            0)
                # Detener monitor si está activo antes de salir
                if [ -n "$MONITOR_PID" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
                    kill "$MONITOR_PID" 2>/dev/null
                    echo -e "${YELLOW}Monitor detenido${NC}"
                fi
                clear_screen
                echo -e "${GREEN}¡Hasta luego!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Opcion invalida${NC}"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Ejecutar
# =============================================================================

main "$@"
