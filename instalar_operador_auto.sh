#!/usr/bin/env bash
# Instalador automático para "Operador de Centro de Cómputos"
# Ubuntu Server 24.04.2 LTS

set -o errexit
set -o pipefail
set -o nounset

OPERADOR_SRC_DEFAULT="./operador.sh"
OPERADOR_DST="/usr/local/bin/operador.sh"
LOG_FILE="/var/log/operador.log"
BACKUP_DIR="/root/backups"

GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; BOLD="\e[1m"; RESET="\e[0m"
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
err(){ echo -e "${RED}✘${RESET} $*"; }

require_root(){ [[ $EUID -eq 0 ]] || { err "Debe ejecutarse como root (sudo)."; exit 1; }; }

main(){
  require_root
  echo -e "${BOLD}==> Instalando entorno completo para el operador...${RESET}"

  DEBIAN_FRONTEND=noninteractive apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    bash coreutils grep sed gawk tar gzip iproute2 procps util-linux \
    nano curl wget rsync net-tools apache2 mysql-server mysql-client \
    ufw fail2ban rclone git

  ok "Dependencias y servicios instalados."

  systemctl enable --now apache2 mysql fail2ban

  local CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
  sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$CNF" || echo "bind-address = 0.0.0.0" >> "$CNF"
  sed -i 's/^mysqlx-bind-address.*/mysqlx-bind-address = 0.0.0.0/' "$CNF" || echo "mysqlx-bind-address = 0.0.0.0" >> "$CNF"
  systemctl restart mysql
  mysql -uroot -e "CREATE USER IF NOT EXISTS 'adminweb'@'%' IDENTIFIED BY 'AdminWeb123';"
  mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'adminweb'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  ok "MySQL configurado con acceso remoto."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22,2222,80,443,3306/tcp
  ufw --force enable
  ok "Firewall UFW configurado correctamente."

  mkdir -p "$BACKUP_DIR"
  chmod 750 "$BACKUP_DIR"
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE"
  ok "Rutas de logs y backups creadas."

  local src="${1:-$OPERADOR_SRC_DEFAULT}"
  if [[ -f "$src" ]]; then
    cp -a "$src" "$OPERADOR_DST"
    chmod +x "$OPERADOR_DST"
    ok "Operador instalado en $OPERADOR_DST"
  else
    warn "No se encontró '$src'. Copia manualmente tu script a $OPERADOR_DST"
  fi

  systemctl restart apache2 mysql ssh fail2ban
  ok "Servicios reiniciados."

  echo -e "\n${GREEN}✔ Instalación completada.${RESET}"
  echo -e "Ejecute: ${BOLD}sudo operador.sh${RESET}\n"
}

main "$@"
