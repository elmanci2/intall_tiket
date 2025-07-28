#!/bin/bash

BACKEND_DIR="$1"
tput init
echo "🛠️  Configuración inicial del backend"

read -p "Nombre de la instancia (ej: miapp): " INSTANCIA
read -p "Usuario de PostgreSQL: " DB_USER
read -s -p "Contraseña para PostgreSQL y Redis: " DB_PASS
echo ""

POSTGRES_DB="$INSTANCIA"
REDIS_PORT=6379
BACKEND_PORT=4000

sudo bash -c "cat > /root/back_credentials.txt <<EOF
INSTANCIA=${INSTANCIA}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
POSTGRES_DB=${POSTGRES_DB}
EOF"

echo "🔴 Iniciando Redis..."
docker run --name redis-${INSTANCIA} \
  -p ${REDIS_PORT}:6379 \
  -d redis redis-server --requirepass $DB_PASS

echo "🐘 Configurando PostgreSQL..."
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE USER ${DB_USER} SUPERUSER CREATEDB CREATEROLE;
      ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;
CREATE DATABASE ${POSTGRES_DB} OWNER ${DB_USER};
EOF

echo "📦 Generando archivo .env..."
mkdir -p "$BACKEND_DIR"
cat > "$BACKEND_DIR/.env" <<EOF
NODE_ENV=development
BACKEND_URL=http://localhost:${BACKEND_PORT}
FRONTEND_URL=http://localhost:3001
PORT=${BACKEND_PORT}
DB_HOST=localhost
DB_DIALECT=postgres
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_NAME=${POSTGRES_DB}
DB_PORT=5432
JWT_SECRET=jwtsecretlocal
JWT_REFRESH_SECRET=refreshsecretlocal
REDIS_URI=redis://:${DB_PASS}@127.0.0.1:${REDIS_PORT}
REDIS_OPT_LIMITER_MAX=1
REGIS_OPT_LIMITER_DURATION=3000
USER_LIMIT=1
CONNECTIONS_LIMIT=1
CLOSED_SEND_BY_ME=true
EOF

echo "📦 Instalando dependencias con bun..."
cd "$BACKEND_DIR"
bun install

echo "🛠️ Compilando TypeScript..."
npm run build

echo "🗃️ Ejecutando migraciones y seeders..."
npm run db:migrate
npm run db:seed

echo "🚀 Iniciando backend con PM2..."
pm2 start dist/server.js --name ${INSTANCIA}-backend
pm2 save

echo "✅ Backend iniciado en http://localhost:${BACKEND_PORT}"
