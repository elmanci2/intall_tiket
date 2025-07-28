#!/bin/bash

echo "🚨 ADVERTENCIA: Esto eliminará TODO lo relacionado con Docker y Certbot. Docker NO se desinstalará, pero quedará limpio."

read -p "¿Estás seguro que quieres continuar? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "❌ Cancelado."
  exit 1
fi

echo "🧽 Limpiando Docker..."

# 1. Detener y eliminar todos los contenedores
docker container stop $(docker ps -aq) 2>/dev/null
docker container rm -f $(docker ps -aq) 2>/dev/null

# 2. Eliminar imágenes, volúmenes, redes no usadas
docker system prune -a -f --volumes
docker volume prune -f
docker network prune -f
docker builder prune -af

# 3. Limpiar archivos temporales de Docker
sudo rm -rf /var/lib/docker/tmp/*

# 4. Reiniciar servicio Docker
sudo systemctl restart docker
echo "✅ Docker limpiado y reiniciado."

echo "🧹 Limpiando Certbot..."

# 5. Detener y deshabilitar Certbot si está programado
sudo systemctl stop certbot.timer 2>/dev/null
sudo systemctl disable certbot.timer 2>/dev/null

# 6. Eliminar certificados y configuraciones
sudo rm -rf /etc/letsencrypt
sudo rm -rf /var/lib/letsencrypt
sudo rm -rf /var/log/letsencrypt

echo "✅ Certbot y certificados eliminados."

# 7. Preguntar si desea eliminar config de NGINX/Caddy
read -p "¿También deseas eliminar configuraciones de NGINX y/o Caddy? (y/n): " CONFIRM_2
if [[ "$CONFIRM_2" == "y" ]]; then
  sudo rm -rf /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/caddy/Caddyfile
  echo "🧨 Configuraciones de NGINX y/o Caddy eliminadas."
fi

echo "🎉 Todo limpio. Docker y Certbot como nuevos."





set -e

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

install_if_missing() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${GREEN}🧩 Instalando $1...${RESET}"
    eval "$2"
  else
    echo -e "${GREEN}✔️ $1 ya está instalado${RESET}"
  fi
}

# Pedir URL del repositorio
read -p "📦 URL del repositorio a clonar: " REPO_URL
REPO_NAME=$(basename "$REPO_URL" .git)

# Guardar la ruta del directorio del instalador
INSTALLER_DIR="$(pwd)"

# Subir un nivel fuera de "instalador/"
cd ..

# Verificar si la carpeta ya existe
if [ -d "$REPO_NAME" ]; then
  echo -e "${YELLOW}📁 La carpeta '$REPO_NAME' ya existe. Usando carpeta existente...${RESET}"
  cd "$REPO_NAME"
  
  # Opcional: actualizar el repositorio existente
  if [ -d ".git" ]; then
    echo -e "${GREEN}🔄 Actualizando repositorio existente...${RESET}"
    git pull origin $(git branch --show-current) || echo -e "${YELLOW}⚠️ No se pudo actualizar automáticamente${RESET}"
  fi
else
  # Clonar repositorio solo si no existe
  echo -e "${GREEN}🔁 Clonando $REPO_URL...${RESET}"
  git clone "$REPO_URL"
  cd "$REPO_NAME"
fi

# Verificar estructura del proyecto
PROJECT_ROOT="$(pwd)"
echo -e "${GREEN}📁 Directorio del proyecto: $PROJECT_ROOT${RESET}"

# Definir rutas directas (sabemos que son backend y frontend)
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

# Verificar que las carpetas existen
if [ ! -d "$BACKEND_DIR" ]; then
  echo -e "${RED}❌ No se encontró la carpeta backend${RESET}"
  echo -e "${YELLOW}📁 Carpetas disponibles:${RESET}"
  ls -la
  exit 1
fi

if [ ! -d "$FRONTEND_DIR" ]; then
  echo -e "${RED}❌ No se encontró la carpeta frontend${RESET}"
  echo -e "${YELLOW}📁 Carpetas disponibles:${RESET}"
  ls -la
  exit 1
fi

# Verificar que tienen package.json
if [ ! -f "$BACKEND_DIR/package.json" ]; then
  echo -e "${RED}❌ No se encontró package.json en la carpeta backend${RESET}"
  exit 1
fi

if [ ! -f "$FRONTEND_DIR/package.json" ]; then
  echo -e "${RED}❌ No se encontró package.json en la carpeta frontend${RESET}"
  exit 1
fi

echo -e "${GREEN}✔️ Encontradas carpetas: backend y frontend${RESET}"

# Requisitos
echo -e "${GREEN}🔧 Verificando dependencias...${RESET}"
install_if_missing curl "sudo apt update && sudo apt install -y curl"
install_if_missing git "sudo apt install -y git"
install_if_missing node "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
install_if_missing npm "sudo apt install -y npm"
install_if_missing pm2 "sudo npm install -g pm2"

# Instalar Bun si no existe
if ! command -v bun &>/dev/null; then
  echo -e "${GREEN}🧩 Instalando Bun...${RESET}"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  # Agregar a bashrc para futuras sesiones
  echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
else
  echo -e "${GREEN}✔️ Bun ya está instalado${RESET}"
fi

# Cargar Bun para esta sesión
export PATH="$HOME/.bun/bin:$PATH"

# Verificar que los scripts del instalador existen
if [ ! -f "$INSTALLER_DIR/back.sh" ]; then
  echo -e "${RED}❌ No se encontró $INSTALLER_DIR/back.sh${RESET}"
  exit 1
fi

if [ ! -f "$INSTALLER_DIR/front.sh" ]; then
  echo -e "${RED}❌ No se encontró $INSTALLER_DIR/front.sh${RESET}"
  exit 1
fi

# Ejecutar scripts en sus carpetas (usando las rutas detectadas)
echo -e "${GREEN}🚀 Ejecutando configuración del backend...${RESET}"
bash "$INSTALLER_DIR/back.sh" "$BACKEND_DIR"

echo -e "${GREEN}🚀 Ejecutando configuración del frontend...${RESET}"
bash "$INSTALLER_DIR/front.sh" "$FRONTEND_DIR"

echo -e "${GREEN}🎉 ¡Todo está listo! Backend y frontend configurados correctamente.${RESET}"
echo -e "${GREEN}📝 Revisa los logs anteriores para ver las URLs de acceso.${RESET}"