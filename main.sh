#!/bin/bash
set -e

GREEN="\033[0;32m"
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

# Clonar repositorio
echo -e "${GREEN}🔁 Clonando $REPO_URL...${RESET}"
git clone "$REPO_URL"
cd "$REPO_NAME"

# Requisitos
install_if_missing curl "sudo apt install -y curl"
install_if_missing git "sudo apt install -y git"
install_if_missing node "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
install_if_missing npm "sudo apt install -y npm"
install_if_missing pm2 "sudo npm install -g pm2"
install_if_missing bun "curl -fsSL https://bun.sh/install | bash && export PATH=\"\$HOME/.bun/bin:\$PATH\""

export PATH="$HOME/.bun/bin:$PATH"

# Ejecutar scripts en sus carpetas
echo -e "${GREEN}🚀 Ejecutando backend...${RESET}"
bash ./back/back.sh "$(pwd)/back"

echo -e "${GREEN}🚀 Ejecutando frontend...${RESET}"
bash ./front/front.sh "$(pwd)/front"

echo -e "${GREEN}🎉 Hola, soy Susana. Todo está listo, ¡a trabajar!${RESET}"
