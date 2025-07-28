#!/bin/bash
set -e

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
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

# Requisitos
install_if_missing curl "sudo apt install -y curl"
install_if_missing git "sudo apt install -y git"
install_if_missing node "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
install_if_missing npm "sudo apt install -y npm"
install_if_missing pm2 "sudo npm install -g pm2"
install_if_missing bun "curl -fsSL https://bun.sh/install | bash && export PATH=\"\$HOME/.bun/bin:\$PATH\""

# Cargar Bun para esta sesión
export PATH="$HOME/.bun/bin:$PATH"

# Ejecutar scripts en sus carpetas (relativas al proyecto clonado)
echo -e "${GREEN}🚀 Ejecutando backend...${RESET}"
bash ./back.sh "$(pwd)/back"

echo -e "${GREEN}🚀 Ejecutando frontend...${RESET}"
bash ./front.sh "$(pwd)/front"

echo -e "${GREEN}🎉 Hola, soy Susana. Todo está listo, ¡a trabajar!${RESET}"