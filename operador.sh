#!/usr/bin/env bash
# ==============================================
# OPERADOR DE CENTRO DE CÓMPUTOS - Versión 4.0
# Ubuntu Server 24.04.2 LTS
# Desarrollado por Mateo Abreus
# ==============================================

set -o errexit
set -o pipefail
set -o nounset

VERSION="4.0"
GIT_REPO="https://github.com/MateoAbreus/operador-centro-computos.git"
LOG_FILE="/var/log/operador.log"
BACKUP_DIR="/root/backups"

# === COLORES ===
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BLUE="\e[34m"; BOLD="\e[1m"; RESET="\e[0m"
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
err(){ echo -e "${RED}✘${RESET} $*"; }
info(){ echo -e "${BLUE}ℹ${RESET} $*"; }

require_root(){ [[ $EUID -eq 0 ]] || { err "Debe ejecutarse como root (sudo)."; exit 1; }; }

rotar_log(){
  [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -gt 5242880 ]] && mv "$LOG_FILE" "${LOG_FILE}_$(date +%F_%H%M%S)"
  touch "$LOG_FILE"; chmod 640 "$LOG_FILE"
}
registrar_log(){ rotar_log; echo "$(date '+%F %T') - $*" >> "$LOG_FILE"; }

pausa(){ echo; read -rp "Presione Enter para continuar..." _; }

# ===================================================
#     FUNCIONES DE INSTALACIÓN / CONFIGURACIÓN
# ===================================================

instalar_auto(){
  info "Instalando entorno completo..."
  DEBIAN_FRONTEND=noninteractive apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    bash coreutils grep sed gawk tar gzip iproute2 procps util-linux \
    nano curl wget rsync net-tools apache2 mysql-server mysql-client \
    ufw fail2ban rclone git
  ok "Dependencias instaladas."

  systemctl enable --now apache2 mysql fail2ban
  local CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
  sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$CNF" || echo "bind-address = 0.0.0.0" >> "$CNF"
  sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address = 0.0.0.0/' "$CNF" || echo "mysqlx-bind-address = 0.0.0.0" >> "$CNF"
  systemctl restart mysql
  mysql -uroot -e "CREATE USER IF NOT EXISTS 'adminweb'@'%' IDENTIFIED BY 'AdminWeb123';"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'adminweb'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  ok "MySQL configurado para acceso remoto con usuario 'adminweb'."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22,2222,80,443,3306/tcp
  ufw --force enable
  ok "Firewall UFW configurado."

  systemctl restart apache2 mysql ssh fail2ban
  mkdir -p "$BACKUP_DIR"; chmod 750 "$BACKUP_DIR"
  touch "$LOG_FILE"; chmod 640 "$LOG_FILE"
  ok "Entorno listo. Log en $LOG_FILE"
  registrar_log "Instalación automática completada."
}

configurar_manual(){
  info "Configuración manual: instalando dependencias básicas..."
  apt update -y
  apt install -y apache2 mysql-server mysql-client rclone ufw fail2ban nano curl wget git
  systemctl enable --now apache2 mysql fail2ban
  ufw --force enable
  ufw allow 22,2222,80,443,3306/tcp
  ok "Configuración manual completada."
  registrar_log "Configuración manual realizada."
}

actualizar_git(){
  info "Actualizando desde GitHub..."
  apt install -y git >/dev/null 2>&1
  local tmp="/tmp/operador_update"
  rm -rf "$tmp"
  git clone "$GIT_REPO" "$tmp"
  cp -f "$tmp/operador.sh" /usr/local/bin/operador.sh
  chmod +x /usr/local/bin/operador.sh
  rm -rf "$tmp"
  ok "Script actualizado desde GitHub."
  registrar_log "Actualización completada desde GitHub."
}

menu_configuracion(){
  while true; do
    clear
    echo -e "${BOLD}=== CONFIGURACIÓN DEL SISTEMA ===${RESET}"
    echo "1) Configurar manualmente"
    echo "2) Configurar automáticamente"
    echo "3) Actualizar desde GitHub"
    echo "0) Volver"
    read -rp "Seleccione una opción: " opt
    case "$opt" in
      1) configurar_manual; pausa ;;
      2) instalar_auto; pausa ;;
      3) actualizar_git; pausa ;;
      0) break ;;
      *) warn "Opción inválida."; pausa ;;
    esac
  done
}

# ===================================================
#           FUNCIONALIDADES PRINCIPALES
# ===================================================

menu_servicios(){
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Servicios ---${RESET}
1) Ver estado de Apache
2) Reiniciar Apache
3) Ver estado de SSH
4) Reiniciar SSH
5) Monitoreo CPU/RAM/Disco
0) Volver"
    read -rp "Elija opción: " op
    case "$op" in
      1) systemctl --no-pager status apache2 | head -n 20 ;;
      2) systemctl restart apache2 && ok "Apache reiniciado." ;;
      3) systemctl --no-pager status ssh | head -n 20 ;;
      4) systemctl restart ssh && ok "SSH reiniciado." ;;
      5)
        echo "CPU:"; top -b -n1 | head -n5
        echo; free -h; echo; df -h | awk 'NR==1 || $6 ~ /^\//'
        ;;
      0) break ;;
      *) warn "Opción inválida." ;;
    esac; pausa
  done
}

menu_red(){
  while true; do
    clear
    echo -e "${BOLD}--- Gestión de Red ---${RESET}
1) Ver IPs
2) Hacer ping
3) Ver rutas
0) Volver"
    read -rp "Opción: " net
    case "$net" in
      1) ip -br a ;;
      2) read -rp "Host/IP: " h; ping -c 4 "$h" ;;
      3) ip route ;;
      0) break ;;
      *) warn "Opción inválida." ;;
    esac; pausa
  done
}

menu_procesos(){
  while true; do
    clear
    echo -e "${BOLD}--- Procesos ---${RESET}
1) Top 15 por memoria
2) Matar proceso por PID
0) Volver"
    read -rp "Opción: " p
    case "$p" in
      1) ps aux --sort=-%mem | head -n 15 ;;
      2)
        read -rp "PID: " pid
        kill "$pid" && ok "Proceso $pid terminado." || warn "No se pudo finalizar."
        ;;
      0) break ;;
    esac; pausa
  done
}

backup_local(){
  local src="$1" name="$2"
  mkdir -p "$BACKUP_DIR"
  local out="${BACKUP_DIR}/${name}_$(date +%F_%H%M%S).tar.gz"
  tar -czf "$out" "$src"
  chmod 600 "$out"
  ok "Respaldo creado: $out"
  registrar_log "Backup de $src → $out"
}

menu_backups(){
  while true; do
    clear
    echo -e "${BOLD}--- Respaldos ---${RESET}
1) Respaldar /etc
2) Respaldar /var/www
3) Respaldar ruta personalizada
0) Volver"
    read -rp "Opción: " b
    case "$b" in
      1) backup_local "/etc" "etc" ;;
      2) backup_local "/var/www" "www" ;;
      3)
        read -rp "Ruta: " r
        [[ -e "$r" ]] && backup_local "$r" "$(basename "$r")" || warn "No existe."
        ;;
      0) break ;;
    esac; pausa
  done
}

menu_usuarios(){
  while true; do
    clear
    echo -e "${BOLD}--- Usuarios ---${RESET}
1) Listar usuarios
2) Crear usuario
3) Eliminar usuario
0) Volver"
    read -rp "Opción: " u
    case "$u" in
      1) cut -d: -f1 /etc/passwd | sort ;;
      2)
        read -rp "Nombre: " name
        adduser --gecos "" "$name"
        ok "Usuario $name creado."
        ;;
      3)
        read -rp "Usuario a eliminar: " del
        deluser --remove-home "$del"
        ok "Usuario $del eliminado."
        ;;
      0) break ;;
    esac; pausa
  done
}

menu_bd(){
  while true; do
    clear
    echo -e "${BOLD}--- Bases de Datos (MySQL) ---${RESET}
1) Crear DB
2) Listar DBs
3) Eliminar DB
0) Volver"
    read -rp "Opción: " db
    case "$db" in
      1) read -rp "Nombre: " n; mysql -uroot -p -e "CREATE DATABASE \`$n\`;" ;;
      2) mysql -uroot -p -e "SHOW DATABASES;" ;;
      3) read -rp "DB a eliminar: " n; mysql -uroot -p -e "DROP DATABASE \`$n\`;" ;;
      0) break ;;
    esac; pausa
  done
}

menu_logs(){
  while true; do
    clear
    echo -e "${BOLD}--- Logs del sistema ---${RESET}
1) Syslog
2) Auth.log
3) Apache access.log
4) Apache error.log
0) Volver"
    read -rp "Opción: " l
    case "$l" in
      1) tail -n 20 /var/log/syslog ;;
      2) tail -n 20 /var/log/auth.log ;;
      3) tail -n 20 /var/log/apache2/access.log ;;
      4) tail -n 20 /var/log/apache2/error.log ;;
      0) break ;;
    esac; pausa
  done
}

# ===================================================
#                 MENÚ PRINCIPAL
# ===================================================
menu_principal(){
  require_root
  while true; do
    clear
    echo -e "${BOLD}==============================================="
    echo "     OPERADOR DE CENTRO DE CÓMPUTOS v$VERSION"
    echo "===============================================${RESET}"
    echo "1) Administración de servicios"
    echo "2) Gestión de red"
    echo "3) Gestión de procesos"
    echo "4) Respaldos"
    echo "5) Usuarios y grupos"
    echo "6) Bases de datos"
    echo "7) Logs del sistema"
    echo "8) Configuración / Instalación"
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
      8) menu_configuracion ;;
      0) registrar_log "Script cerrado por usuario."; exit 0 ;;
      *) warn "Opción inválida." ;;
    esac
    pausa
  done
}

menu_principal
