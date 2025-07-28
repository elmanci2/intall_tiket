#!/bin/bash

FRONT_DIR="$1"

read -p "🔤 Nombre del sitio (ej: miapp): " NAME
read -p "🌐 URL del backend (ej: https://api.midominio.com): " BACKEND_URL
read -p "🔐 Usuario admin: " ADMIN_USER
read -s -p "🔑 Contraseña admin: " ADMIN_PASS
echo
read -p "📦 Puerto en el que correrá el frontend (ej: 3001): " PORT

CRED_FILE="$HOME/back_credential.txt"
echo "💾 Guardando credenciales en $CRED_FILE"
echo "user=$ADMIN_USER" > "$CRED_FILE"
echo "pass=$ADMIN_PASS" >> "$CRED_FILE"

if ! command -v bun &> /dev/null; then
  echo "🍞 Instalando Bun..."
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

cd "$FRONT_DIR"

echo "📦 Instalando dependencias y compilando..."
bun install
bun run build

echo "📝 Configurando .env..."
cat > .env <<EOF
REACT_APP_BACKEND_URL=${BACKEND_URL}
REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24
EOF

echo "🌐 Creando servidor Express..."
cat > server.js <<EOF
const express = require('express');
const path = require('path');
const app = express();
app.use(express.static(path.join(__dirname, 'build')));
app.get('/*', (req, res) => {
  res.sendFile(path.join(__dirname, 'build', 'index.html'));
});
app.listen(${PORT}, () => {
  console.log('Frontend corriendo en el puerto ${PORT}');
});
EOF

echo "🚀 Ejecutando con pm2..."
pm2 start server.js --name "${NAME}-frontend"
pm2 save

echo "✅ Listo. El frontend está corriendo en http://localhost:${PORT}"
