#!/bin/bash
set -e

# Colores para output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

BACKEND_DIR="$1"
tput init

echo -e "${GREEN}🛠️  Configuración inicial del backend${RESET}"
echo -e "${BLUE}📁 Directorio backend: $BACKEND_DIR${RESET}"

# Verificar que el directorio existe
if [ ! -d "$BACKEND_DIR" ]; then
    echo -e "${RED}❌ Error: El directorio $BACKEND_DIR no existe${RESET}"
    exit 1
fi

# Verificar que existe package.json
if [ ! -f "$BACKEND_DIR/package.json" ]; then
    echo -e "${RED}❌ Error: No se encontró package.json en $BACKEND_DIR${RESET}"
    exit 1
fi

# Función para limpiar contenedores Docker existentes
cleanup_docker() {
    echo -e "${YELLOW}🧹 Limpiando contenedores Docker existentes...${RESET}"
    
    # Obtener todos los contenedores en ejecución
    RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null || true)
    
    if [ -n "$RUNNING_CONTAINERS" ]; then
        echo -e "${YELLOW}📋 Contenedores en ejecución encontrados:${RESET}"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        
        echo -e "${YELLOW}🛑 Deteniendo todos los contenedores...${RESET}"
        docker stop $RUNNING_CONTAINERS 2>/dev/null || true
        
        echo -e "${YELLOW}🗑️  Removiendo contenedores detenidos...${RESET}"
        docker rm $RUNNING_CONTAINERS 2>/dev/null || true
    else
        echo -e "${GREEN}✅ No hay contenedores en ejecución${RESET}"
    fi
    
    # Limpiar contenedores detenidos adicionales
    STOPPED_CONTAINERS=$(docker ps -aq 2>/dev/null || true)
    if [ -n "$STOPPED_CONTAINERS" ]; then
        echo -e "${YELLOW}🗑️  Removiendo contenedores detenidos adicionales...${RESET}"
        docker rm $STOPPED_CONTAINERS 2>/dev/null || true
    fi
    
    # Opcional: limpiar redes no utilizadas
    echo -e "${YELLOW}🌐 Limpiando redes no utilizadas...${RESET}"
    docker network prune -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Limpieza Docker completada${RESET}"
}

# Función para verificar si un puerto está ocupado
check_port() {
    local port=$1
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        return 0  # Puerto ocupado
    else
        return 1  # Puerto libre
    fi
}

# Limpiar Docker antes de empezar
cleanup_docker

# Solicitar información del usuario
read -p "Nombre de la instancia (ej: miapp): " INSTANCIA
read -p "Usuario de PostgreSQL: " DB_USER
read -s -p "Contraseña para PostgreSQL y Redis: " DB_PASS
echo ""

POSTGRES_DB="$INSTANCIA"
REDIS_PORT=6379
BACKEND_PORT=4000

# Verificar puertos antes de continuar
echo -e "${BLUE}🔍 Verificando disponibilidad de puertos...${RESET}"

if check_port $REDIS_PORT; then
    echo -e "${YELLOW}⚠️  Puerto $REDIS_PORT (Redis) está ocupado, pero continuamos tras la limpieza Docker${RESET}"
fi

if check_port $BACKEND_PORT; then
    echo -e "${YELLOW}⚠️  Puerto $BACKEND_PORT (Backend) está ocupado${RESET}"
    # Intentar detener proceso PM2 existente
    pm2 delete "${INSTANCIA}-backend" 2>/dev/null || true
fi

# Guardar credenciales
echo -e "${BLUE}💾 Guardando credenciales...${RESET}"
sudo bash -c "cat > /root/back_credentials.txt <<EOF
INSTANCIA=${INSTANCIA}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
POSTGRES_DB=${POSTGRES_DB}
REDIS_PORT=${REDIS_PORT}
BACKEND_PORT=${BACKEND_PORT}
FECHA_INSTALACION=\$(date)
EOF"

echo -e "${RED}🔴 Iniciando Redis...${RESET}"
if ! docker run --name redis-${INSTANCIA} \
  -p ${REDIS_PORT}:6379 \
  -d redis redis-server --requirepass "$DB_PASS"; then
    echo -e "${RED}❌ Error al iniciar Redis${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ Redis iniciado correctamente${RESET}"

echo -e "${BLUE}🐘 Configurando PostgreSQL...${RESET}"
if ! sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE USER ${DB_USER} SUPERUSER CREATEDB CREATEROLE;
      ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;

-- Intentar crear la base de datos (ignorar si ya existe)
SELECT 'CREATE DATABASE ${POSTGRES_DB} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_DB}');
\gexec
EOF
then
    echo -e "${RED}❌ Error en la configuración de PostgreSQL${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ PostgreSQL configurado correctamente${RESET}"

echo -e "${BLUE}📦 Generando archivo .env...${RESET}"
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

echo -e "${GREEN}✅ Archivo .env creado${RESET}"

echo -e "${BLUE}📦 Instalando dependencias...${RESET}"
cd "$BACKEND_DIR"

# Intentar con bun primero, luego npm
if command -v bun &>/dev/null; then
    echo -e "${GREEN}Using bun for package installation...${RESET}"
    if ! bun install; then
        echo -e "${YELLOW}⚠️  Bun falló, intentando con npm...${RESET}"
        npm install || {
            echo -e "${RED}❌ Error instalando dependencias${RESET}"
            exit 1
        }
    fi
else
    echo -e "${GREEN}Using npm for package installation...${RESET}"
    npm install || {
        echo -e "${RED}❌ Error instalando dependencias${RESET}"
        exit 1
    }
fi

echo -e "${GREEN}✅ Dependencias instaladas${RESET}"

echo -e "${BLUE}🛠️ Compilando TypeScript...${RESET}"
if ! npm run build; then
    echo -e "${RED}❌ Error en la compilación${RESET}"
    exit 1
fi

echo -e "${GREEN}✅ Compilación completada${RESET}"

echo -e "${BLUE}🗃️ Ejecutando migraciones y seeders...${RESET}"
if ! npm run db:migrate; then
    echo -e "${RED}❌ Error en las migraciones${RESET}"
    exit 1
fi

if ! npm run db:seed; then
    echo -e "${YELLOW}⚠️  Los seeders fallaron, pero continuando...${RESET}"
fi

echo -e "${GREEN}✅ Base de datos configurada${RESET}"

echo -e "${BLUE}🚀 Iniciando backend con PM2...${RESET}"

# Verificar que el archivo compilado existe
if [ ! -f "dist/server.js" ]; then
    echo -e "${RED}❌ Error: No se encontró dist/server.js${RESET}"
    exit 1
fi

# Detener proceso PM2 existente si existe
pm2 delete "${INSTANCIA}-backend" 2>/dev/null || true

# Iniciar el nuevo proceso
if ! pm2 start dist/server.js --name "${INSTANCIA}-backend"; then
    echo -e "${RED}❌ Error iniciando con PM2${RESET}"
    exit 1
fi

pm2 save

echo -e "${GREEN}✅ Backend iniciado exitosamente${RESET}"
echo -e "${GREEN}🌐 Backend disponible en: http://localhost:${BACKEND_PORT}${RESET}"
echo -e "${GREEN}📝 Credenciales guardadas en: /root/back_credentials.txt${RESET}"
echo -e "${BLUE}📊 Estado de PM2:${RESET}"
pm2 status