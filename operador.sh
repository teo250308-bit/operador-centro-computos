#!/usr/bin/env bash
# ==============================================
# OPERADOR DE CENTRO DE CÓMPUTOS - Versión 5.0
# Ubuntu Server 24.04.2 LTS
# Desarrollado por Mateo Abreus (teo250308-bit)
# ==============================================

set -o errexit
set -o pipefail
set -o nounset

VERSION="5.0"
LOG_FILE="/var/log/operador.log"
BACKUP_DIR="/root/backups"
GIT_REPO="https://github.com/teo250308-bit/operador-centro-computos.git"
INSTALLER_URL="https://raw.githubusercontent.com/teo250308-bit/operador-centro-computos/main/instalar_operador_auto.sh"

# --- COLORES ---
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; BOLD="\e[1m"; RESET="\e[0m"
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
err(){ echo -e "${RED}✘${RESET} $*"; }
info(){ echo -e "${BLUE}ℹ${RESET} $*"; }

USER_EXEC="$(whoami)"
TTY_EXEC="$(tty)"

require_root(){ [[ $EUID -eq 0 ]] || { err "Debe ejecutarse como root (sudo)."; exit 1; }; }

rotar_log(){
  [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -gt 5242880 ]] && mv "$LOG_FILE" "${LOG_FILE}_$(date +%F_%H%M%S)"
  touch "$LOG_FILE"; chmod 640 "$LOG_FILE"
}

registrar_log(){
  rotar_log
  local tipo="INFO"
  [[ "$1" =~ ^\[.*\]$ ]] && tipo="${1}" && shift
  echo "$(date '+%F %T') ${tipo} [${USER_EXEC}@${TTY_EXEC}] $*" >> "$LOG_FILE"
}

pausa(){ echo; read -rp "Presione Enter para continuar..." _; }

trap 'registrar_log "[ERROR]" "Error en la línea $LINENO - comando: $BASH_COMMAND"' ERR

# ===================================================
#                  FUNCIONES PRINCIPALES
# ===================================================

menu_servicios(){
  registrar_log "[INFO]" "Entrando al menú de servicios"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Servicios ---${RESET}"
    echo "1) Ver estado de Apache"
    echo "2) Reiniciar Apache"
    echo "3) Ver estado de SSH"
    echo "4) Reiniciar SSH"
    echo "5) Monitoreo CPU/RAM/Disco"
    echo "0) Volver"
    read -rp "Opción: " op
    case "$op" in
      1) registrar_log "[ACTION]" "Consulta estado Apache"; systemctl status apache2 --no-pager | head -n 20 ;;
      2) systemctl restart apache2 && ok "Apache reiniciado." && registrar_log "[OK]" "Apache reiniciado correctamente" ;;
      3) registrar_log "[ACTION]" "Consulta estado SSH"; systemctl status ssh --no-pager | head -n 20 ;;
      4) systemctl restart ssh && ok "SSH reiniciado." && registrar_log "[OK]" "SSH reiniciado correctamente" ;;
      5)
        echo "--- CPU ---"; top -b -n1 | head -n 5
        echo "--- RAM ---"; free -h
        echo "--- DISCO ---"; df -h | awk 'NR==1 || $6 ~ /^\//'
        registrar_log "[ACTION]" "Consulta de CPU, RAM y DISCO"
        ;;
      0) break ;;
      *) warn "Opción inválida"; registrar_log "[WARN]" "Opción inválida menú servicios" ;;
    esac; pausa
  done
}

menu_red(){
  registrar_log "[INFO]" "Entrando al menú de red"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Red ---${RESET}"
    echo "1) Ver IPs"
    echo "2) Probar conectividad"
    echo "0) Volver"
    read -rp "Opción: " net
    case "$net" in
      1) ip a; registrar_log "[ACTION]" "Consulta IP del servidor" ;;
      2) ping -c 4 google.com; registrar_log "[ACTION]" "Ping de prueba a google.com" ;;
      0) break ;;
      *) warn "Opción inválida"; registrar_log "[WARN]" "Opción inválida menú red" ;;
    esac; pausa
  done
}

menu_procesos(){
  registrar_log "[INFO]" "Entrando al menú de procesos"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Procesos ---${RESET}"
    echo "1) Ver top de procesos"
    echo "2) Matar proceso por PID"
    echo "0) Volver"
    read -rp "Opción: " proc
    case "$proc" in
      1) ps aux --sort=-%mem | head -n 15; registrar_log "[ACTION]" "Visualización de procesos activos" ;;
      2) read -rp "PID a eliminar: " pid; kill -9 "$pid" && registrar_log "[OK]" "Proceso $pid terminado" || registrar_log "[WARN]" "No se pudo eliminar proceso $pid" ;;
      0) break ;;
    esac; pausa
  done
}

menu_backups(){
  registrar_log "[INFO]" "Entrando al menú de respaldos"
  mkdir -p "$BACKUP_DIR"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Respaldos ---${RESET}"
    echo "1) Respaldar /etc"
    echo "2) Respaldar /var/www"
    echo "3) Respaldar carpeta personalizada"
    echo "4) Respaldar carpeta a Google Drive (rclone)"
    echo "0) Volver"
    read -rp "Opción: " bkp
    case "$bkp" in
      1) tar -czf "$BACKUP_DIR/etc_$(date +%F).tar.gz" /etc && ok "Respaldo /etc creado" && registrar_log "[OK]" "Respaldo local /etc" ;;
      2) tar -czf "$BACKUP_DIR/www_$(date +%F).tar.gz" /var/www && ok "Respaldo /var/www creado" && registrar_log "[OK]" "Respaldo local /var/www" ;;
      3)
        read -rp "Ruta local: " ruta
        [[ -d "$ruta" ]] || { warn "Ruta inválida"; continue; }
        tar -czf "$BACKUP_DIR/$(basename "$ruta")_$(date +%F).tar.gz" "$ruta"
        ok "Respaldo creado para $ruta"
        registrar_log "[OK]" "Respaldo manual de $ruta"
        ;;
      4)
        read -rp "Ruta local a subir: " ruta
        read -rp "Carpeta destino en Google Drive: " dest
        rclone copy "$ruta" gdrive:"$dest" -P && ok "Respaldo remoto subido" && registrar_log "[OK]" "Backup remoto de $ruta → Drive/$dest"
        ;;
      0) break ;;
    esac; pausa
  done
}

menu_usuarios(){
  registrar_log "[INFO]" "Entrando al menú de usuarios"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Usuarios ---${RESET}"
    echo "1) Listar usuarios"
    echo "2) Listar grupos"
    echo "3) Crear usuario (con grupo)"
    echo "4) Eliminar usuario"
    echo "0) Volver"
    read -rp "Opción: " usr
    case "$usr" in
      1) cut -d: -f1 /etc/passwd | sort; registrar_log "[ACTION]" "Listado de usuarios" ;;
      2) cut -d: -f1 /etc/group | sort; registrar_log "[ACTION]" "Listado de grupos" ;;
      3)
        read -rp "Nombre de usuario: " u
        read -rp "Grupo al que asignar: " g
        adduser --gecos "" "$u"
        usermod -aG "$g" "$u"
        ok "Usuario '$u' creado en grupo '$g'"
        registrar_log "[OK]" "Usuario $u creado en grupo $g"
        ;;
      4)
        read -rp "Usuario a eliminar: " u
        deluser --remove-home "$u"
        ok "Usuario '$u' eliminado"
        registrar_log "[OK]" "Usuario $u eliminado"
        ;;
      0) break ;;
    esac; pausa
  done
}

menu_bd(){
  registrar_log "[INFO]" "Entrando al menú de bases de datos"
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Bases de Datos (MySQL) ---${RESET}"
    echo "1) Crear base de datos"
    echo "2) Listar bases de datos"
    echo "3) Eliminar base de datos"
    echo "0) Volver"
    read -rp "Opción: " db
    case "$db" in
      1) read -rp "Nombre DB: " n; mysql -uroot -p -e "CREATE DATABASE \`$n\`;" && registrar_log "[OK]" "DB $n creada" ;;
      2) mysql -uroot -p -e "SHOW DATABASES;"; registrar_log "[ACTION]" "Listado de DBs" ;;
      3) read -rp "DB a eliminar: " n; mysql -uroot -p -e "DROP DATABASE \`$n\`;" && registrar_log "[OK]" "DB $n eliminada" ;;
      0) break ;;
    esac; pausa
  done
}

menu_logs(){
  registrar_log "[INFO]" "Entrando al menú de logs del sistema"
  while true; do
    clear
    echo -e "${BOLD}--- Registros del Sistema ---${RESET}"
    echo "1) Últimas 20 líneas de syslog"
    echo "2) Últimos intentos SSH (auth.log)"
    echo "3) Logs de Apache access.log"
    echo "4) Logs de Apache error.log"
    echo "5) Ver 4 logs principales"
    echo "0) Volver"
    read -rp "Opción: " log
    case "$log" in
      1) tail -n 20 /var/log/syslog ;;
      2) tail -n 20 /var/log/auth.log ;;
      3) tail -n 20 /var/log/apache2/access.log ;;
      4) tail -n 20 /var/log/apache2/error.log ;;
      5)
        echo "--- syslog ---"; tail -n 10 /var/log/syslog
        echo "--- auth.log ---"; tail -n 10 /var/log/auth.log
        echo "--- apache error.log ---"; tail -n 10 /var/log/apache2/error.log
        echo "--- dmesg ---"; dmesg | tail -n 10
        ;;
      0) break ;;
    esac; pausa
  done
}

menu_log_interno(){
  registrar_log "[INFO]" "Acceso al menú de log interno"
  while true; do
    clear
    echo -e "${BOLD}--- Log Interno del Script ---${RESET}"
    echo "1) Ver últimos 30 eventos"
    echo "2) Borrar log interno"
    echo "0) Volver"
    read -rp "Opción: " l
    case "$l" in
      1) tail -n 30 "$LOG_FILE" ;;
      2)
        read -rp "¿Seguro que desea borrar el log? (s/n): " c
        if [[ "$c" =~ ^[Ss]$ ]]; then
          truncate -s 0 "$LOG_FILE"
          ok "Log interno vaciado"
          registrar_log "[ACTION]" "Log interno vaciado manualmente"
        fi
        ;;
      0) break ;;
    esac; pausa
  done
}

# ===================================================
#        CONFIGURACIÓN, INSTALACIÓN Y ACTUALIZACIÓN
# ===================================================

instalar_auto(){
  require_root
  registrar_log "[ACTION]" "Instalación automática iniciada"
  info "Descargando instalador automático desde GitHub..."
  local tmp="/tmp/instalar_operador_auto.sh"
  apt-get install -y curl >/dev/null 2>&1
  if curl -fsSL "$INSTALLER_URL" -o "$tmp"; then
    chmod +x "$tmp"
    bash "$tmp" "$0"
    ok "Instalación automática completada."
    registrar_log "[OK]" "Instalación automática ejecutada correctamente"
  else
    err "No se pudo descargar el instalador desde GitHub"
    registrar_log "[ERROR]" "Fallo la descarga del instalador automático"
  fi
}

configurar_manual(){
  registrar_log "[ACTION]" "Configuración manual iniciada"
  info "Instalando dependencias del sistema..."
  apt update -y && apt install -y apache2 mysql-server mysql-client rclone ufw fail2ban nano curl wget git
  systemctl enable --now apache2 mysql fail2ban
  ufw --force enable
  ufw allow 22,2222,80,443,3306/tcp
  ok "Configuración manual completada."
  registrar_log "[OK]" "Configuración manual completada exitosamente"
}

actualizar_git(){
  require_root
  registrar_log "[ACTION]" "Actualización desde GitHub iniciada"
  apt install -y git >/dev/null 2>&1
  local tmp="/tmp/operador_update"
  rm -rf "$tmp"
  if git clone "$GIT_REPO" "$tmp"; then
    cp -f "$tmp/operador.sh" /usr/local/bin/operador.sh
    chmod +x /usr/local/bin/operador.sh
    rm -rf "$tmp"
    ok "Script actualizado desde GitHub (${GIT_REPO})."
    registrar_log "[OK]" "Actualización completada desde GitHub"
  else
    err "No se pudo clonar el repositorio desde GitHub."
    registrar_log "[ERROR]" "Falló la actualización desde GitHub"
  fi
}

menu_configuracion(){
  registrar_log "[INFO]" "Entrando al menú de configuración e instalación"
  while true; do
    clear
    echo -e "${BOLD}--- Configuración / Instalación ---${RESET}"
    echo "1) Configurar manualmente el sistema"
    echo "2) Instalar automáticamente desde GitHub"
    echo "3) Actualizar script desde GitHub"
    echo "0) Volver"
    read -rp "Opción: " cfg
    case "$cfg" in
      1) configurar_manual ;;
      2) instalar_auto ;;
      3) actualizar_git ;;
      0) break ;;
      *) warn "Opción inválida."; registrar_log "[WARN]" "Opción inválida menú configuración" ;;
    esac
    pausa
  done
}


# ===================================================
#                 MENÚ PRINCIPAL
# ===================================================
menu_principal(){
  require_root
  registrar_log "[INFO]" "Inicio del operador versión $VERSION"
  while true; do
    clear
    echo -e "${BOLD}==============================================="
    echo "     OPERADOR DE CENTRO DE CÓMPUTOS v$VERSION"
    echo "===============================================${RESET}"
    echo "1) Administración de sistemas"
    echo "2) Gestión de redes"
    echo "3) Gestión de procesos"
    echo "4) Gestión de respaldos"
    echo "5) Gestión de usuarios y grupos"
    echo "6) Gestión de bases de datos"
    echo "7) Monitoreo y registros del sistema"
    echo "8) Log interno del script"
    echo "9) Configuración / Instalación"
    echo "0) Salir"
    read -rp "Seleccione opción: " op
    case "$op" in
      1) menu_servicios ;;
      2) menu_red ;;
      3) menu_procesos ;;
      4) menu_backups ;;
      5) menu_usuarios ;;
      6) menu_bd ;;
      7) menu_logs ;;
      8) menu_log_interno ;;
      9) menu_configuracion ;;
      0) registrar_log "[INFO]" "Script cerrado por usuario"; exit 0 ;;
      *) warn "Opción inválida"; registrar_log "[WARN]" "Opción inválida menú principal" ;;
    esac
    pausa
  done
}

menu_principal
