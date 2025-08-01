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
read -p "Dominio para el backend (ej: api.midominio.com): " BACKEND_DOMAIN
read -p "Email para Certbot/Let's Encrypt: " CERTBOT_EMAIL

POSTGRES_DB="$INSTANCIA"
REDIS_PORT=6379
BACKEND_PORT=4000

# Función para instalar y configurar Nginx (configuración inicial HTTP)
setup_nginx() {
    echo -e "${BLUE}🌐 Configurando Nginx...${RESET}"
    
    # Instalar Nginx si no está instalado
    if ! command -v nginx &>/dev/null; then
        echo -e "${GREEN}📦 Instalando Nginx...${RESET}"
        sudo apt update
        sudo apt install -y nginx
        sudo systemctl enable nginx
    else
        echo -e "${GREEN}✅ Nginx ya está instalado${RESET}"
    fi
    
    # Crear directorios de Nginx si no existen
    echo -e "${BLUE}📁 Verificando/creando directorios de Nginx...${RESET}"
    sudo mkdir -p /etc/nginx/sites-available
    sudo mkdir -p /etc/nginx/sites-enabled
    sudo mkdir -p /var/log/nginx
    sudo mkdir -p /var/www/html
    
    # Verificar que nginx.conf incluye sites-enabled
    if ! sudo grep -q "include /etc/nginx/sites-enabled" /etc/nginx/nginx.conf; then
        echo -e "${YELLOW}⚠️  Agregando include para sites-enabled en nginx.conf...${RESET}"
        sudo sed -i '/http {/a\\tinclude /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    fi
    
    # Crear configuración HTTP inicial (sin SSL)
    echo -e "${BLUE}📝 Creando configuración HTTP inicial...${RESET}"
    sudo tee "/etc/nginx/sites-available/${INSTANCIA}-backend-http" > /dev/null <<EOF
server {
    listen 80;
    server_name ${BACKEND_DOMAIN};
    
    # Para validación de Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Configuración del proxy al backend
    location / {
        proxy_pass http://localhost:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffer_size 4k;
        proxy_buffers 4 32k;
        proxy_busy_buffers_size 64k;
    }
    
    # Configuración para WebSockets (si es necesario)
    location /socket.io/ {
        proxy_pass http://localhost:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Logs
    access_log /var/log/nginx/${INSTANCIA}-backend.access.log;
    error_log /var/log/nginx/${INSTANCIA}-backend.error.log;
}
EOF
    
    # Habilitar la configuración HTTP inicial
    echo -e "${BLUE}🔗 Habilitando configuración HTTP inicial...${RESET}"
    sudo ln -sf "/etc/nginx/sites-available/${INSTANCIA}-backend-http" "/etc/nginx/sites-enabled/${INSTANCIA}-backend"
    
    # Remover configuración por defecto si existe
    sudo rm -f /etc/nginx/sites-enabled/default
    
    echo -e "${GREEN}✅ Configuración HTTP inicial de Nginx creada${RESET}"
}

# Función para crear configuración SSL (se ejecuta después de obtener certificados)
setup_nginx_ssl() {
    echo -e "${BLUE}🔒 Configurando Nginx con SSL...${RESET}"
    
    # Crear configuración completa con SSL
    sudo tee "/etc/nginx/sites-available/${INSTANCIA}-backend-ssl" > /dev/null <<EOF
server {
    listen 80;
    server_name ${BACKEND_DOMAIN};
    
    # Redirigir HTTP a HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${BACKEND_DOMAIN};
    
    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/${BACKEND_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${BACKEND_DOMAIN}/privkey.pem;
    
    # Configuración SSL moderna
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Headers de seguridad
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Configuración del proxy al backend
    location / {
        proxy_pass http://localhost:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffer_size 4k;
        proxy_buffers 4 32k;
        proxy_busy_buffers_size 64k;
    }
    
    # Configuración para WebSockets (si es necesario)
    location /socket.io/ {
        proxy_pass http://localhost:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Logs
    access_log /var/log/nginx/${INSTANCIA}-backend.access.log;
    error_log /var/log/nginx/${INSTANCIA}-backend.error.log;
}
EOF
    
    # Activar configuración SSL
    echo -e "${BLUE}🔗 Activando configuración SSL...${RESET}"
    sudo ln -sf "/etc/nginx/sites-available/${INSTANCIA}-backend-ssl" "/etc/nginx/sites-enabled/${INSTANCIA}-backend"
    
    echo -e "${GREEN}✅ Configuración SSL de Nginx activada${RESET}"
}

# Función para configurar Certbot y SSL
setup_certbot() {
    echo -e "${BLUE}🔒 Configurando Certbot y SSL...${RESET}"
    
    # Instalar Certbot si no está instalado
    if ! command -v certbot &>/dev/null; then
        echo -e "${GREEN}📦 Instalando Certbot...${RESET}"
        sudo apt update
        sudo apt install -y certbot python3-certbot-nginx
    else
        echo -e "${GREEN}✅ Certbot ya está instalado${RESET}"
    fi
    
    # Verificar que el dominio resuelve a esta IP
    echo -e "${YELLOW}🔍 Verificando resolución DNS para ${BACKEND_DOMAIN}...${RESET}"
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "No se pudo obtener IP")
    DOMAIN_IP=$(dig +short ${BACKEND_DOMAIN} 2>/dev/null || echo "No resuelve")
    
    echo -e "${BLUE}📍 IP del servidor: ${SERVER_IP}${RESET}"
    echo -e "${BLUE}📍 IP del dominio: ${DOMAIN_IP}${RESET}"
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo -e "${YELLOW}⚠️  ADVERTENCIA: El dominio no apunta a este servidor${RESET}"
        echo -e "${YELLOW}   Asegúrate de que ${BACKEND_DOMAIN} apunte a ${SERVER_IP}${RESET}"
        read -p "¿Continuar de todas formas? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ Configuración SSL cancelada${RESET}"
            return 1
        fi
    fi
    
    # Obtener certificado SSL usando webroot
    echo -e "${GREEN}🔐 Obteniendo certificado SSL...${RESET}"
    if sudo certbot certonly --webroot \
        --webroot-path=/var/www/html \
        --email "$CERTBOT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$BACKEND_DOMAIN" \
        --non-interactive; then
        
        echo -e "${GREEN}✅ Certificado SSL obtenido exitosamente${RESET}"
        
        # Ahora configurar Nginx con SSL
        setup_nginx_ssl
        
        # Verificar configuración SSL y recargar
        echo -e "${BLUE}🔍 Verificando configuración SSL...${RESET}"
        if sudo nginx -t; then
            sudo systemctl reload nginx
            echo -e "${GREEN}✅ Nginx recargado con configuración SSL${RESET}"
        else
            echo -e "${RED}❌ Error en la configuración SSL de Nginx${RESET}"
            echo -e "${YELLOW}🔧 Manteniendo configuración HTTP${RESET}"
            return 1
        fi
        
        # Configurar renovación automática
        if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
            echo -e "${BLUE}⏰ Configurando renovación automática de certificados...${RESET}"
            (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet --nginx && /usr/bin/systemctl reload nginx") | sudo crontab -
        fi
        
    else
        echo -e "${RED}❌ Error obteniendo certificado SSL${RESET}"
        echo -e "${YELLOW}🔧 El sitio seguirá funcionando con HTTP${RESET}"
        return 1
    fi
}

# Función para diagnosticar problemas de base de datos
diagnose_database() {
    echo -e "${BLUE}🔍 Diagnosticando base de datos...${RESET}"
    
    # Verificar conexión a PostgreSQL
    if sudo -u postgres psql -d ${POSTGRES_DB} -c "\conninfo" &>/dev/null; then
        echo -e "${GREEN}✅ Conexión a PostgreSQL exitosa${RESET}"
    else
        echo -e "${RED}❌ Error de conexión a PostgreSQL${RESET}"
        return 1
    fi
    
    # Listar tablas existentes
    echo -e "${BLUE}📋 Tablas existentes:${RESET}"
    sudo -u postgres psql -d ${POSTGRES_DB} -c "\dt" 2>/dev/null || echo "No se pudieron listar las tablas"
    
    # Verificar estructura de tabla Companies si existe
    if sudo -u postgres psql -d ${POSTGRES_DB} -c "\d \"Companies\"" &>/dev/null; then
        echo -e "${BLUE}🏢 Estructura de tabla Companies:${RESET}"
        sudo -u postgres psql -d ${POSTGRES_DB} -c "\d \"Companies\"" 2>/dev/null || true
        
        echo -e "${BLUE}📊 Datos en Companies:${RESET}"
        sudo -u postgres psql -d ${POSTGRES_DB} -c "SELECT id, name, email FROM \"Companies\" LIMIT 5;" 2>/dev/null || true
    fi
    
    # Verificar si existen índices únicos o constraints
    echo -e "${BLUE}🔒 Constraints únicos:${RESET}"
    sudo -u postgres psql -d ${POSTGRES_DB} -c "
        SELECT tc.constraint_name, tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        WHERE tc.constraint_type = 'UNIQUE' AND tc.table_name IN ('Companies', 'Users');
    " 2>/dev/null || true
}
setup_firewall() {
    echo -e "${BLUE}🔥 Configurando firewall...${RESET}"
    
    if command -v ufw &>/dev/null; then
        # Permitir puertos necesarios
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # Habilitar UFW si no está activo
        if ! sudo ufw status | grep -q "Status: active"; then
            echo "y" | sudo ufw enable
        fi
        
        echo -e "${GREEN}✅ Firewall configurado${RESET}"
        sudo ufw status
    else
        echo -e "${YELLOW}⚠️  UFW no está instalado, se recomienda configurar firewall manualmente${RESET}"
    fi
}

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

# Crear directorio para credenciales si no existe
sudo mkdir -p /root

# Guardar credenciales
echo -e "${BLUE}💾 Guardando credenciales...${RESET}"
sudo bash -c "cat > /root/back_credentials.txt <<EOF
INSTANCIA=${INSTANCIA}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
POSTGRES_DB=${POSTGRES_DB}
REDIS_PORT=${REDIS_PORT}
BACKEND_PORT=${BACKEND_PORT}
BACKEND_DOMAIN=${BACKEND_DOMAIN}
CERTBOT_EMAIL=${CERTBOT_EMAIL}
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
NODE_ENV=production
BACKEND_URL=https://${BACKEND_DOMAIN}
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

    # Aseguramos instalación de baileys
    echo -e "${GREEN}Verificando e instalando @whiskeysockets/baileys...${RESET}"
    bun add @whiskeysockets/baileys || {
        echo -e "${RED}❌ No se pudo instalar @whiskeysockets/baileys${RESET}"
        exit 1
    }
else
    echo -e "${GREEN}Using npm for package installation...${RESET}"
    npm install || {
        echo -e "${RED}❌ Error instalando dependencias${RESET}"
        exit 1
    }

    # También lo instalamos por npm en caso necesario
    echo -e "${GREEN}Verificando e instalando @whiskeysockets/baileys...${RESET}"
    npm install @whiskeysockets/baileys || {
        echo -e "${RED}❌ No se pudo instalar @whiskeysockets/baileys${RESET}"
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

# Verificar si ya existen datos antes de ejecutar seeders
echo -e "${BLUE}🔍 Verificando datos existentes...${RESET}"
EXISTING_DATA=$(sudo -u postgres psql -d ${POSTGRES_DB} -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('Companies', 'Users');" 2>/dev/null || echo "0")

if [[ $EXISTING_DATA -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Detectadas tablas existentes, verificando datos...${RESET}"
    
    # Verificar si ya existe una empresa
    COMPANY_COUNT=$(sudo -u postgres psql -d ${POSTGRES_DB} -t -c "SELECT COUNT(*) FROM \"Companies\";" 2>/dev/null || echo "0")
    
    if [[ $COMPANY_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}📊 Ya existen $COMPANY_COUNT empresa(s) en la base de datos${RESET}"
        echo -e "${BLUE}🔄 Saltando seeders para evitar duplicados...${RESET}"
    else
        echo -e "${BLUE}📝 Ejecutando seeders...${RESET}"
        if ! npm run db:seed; then
            echo -e "${YELLOW}⚠️  Error en seeders, diagnosticando...${RESET}"
            diagnose_database
            
            echo -e "${BLUE}🔍 Intentando seeder individual con más detalles:${RESET}"
            # Intentar ejecutar seeder individual para más información
            npx sequelize db:seed --seed 20200904070005-create-default-company.js 2>&1 || true
        fi
    fi
else
    echo -e "${BLUE}📝 Ejecutando seeders en base de datos vacía...${RESET}"
    if ! npm run db:seed; then
        echo -e "${YELLOW}⚠️  Error en seeders, intentando limpieza y reintento...${RESET}"
        
        # Limpiar datos existentes y reintentar
        echo -e "${BLUE}🧹 Limpiando datos existentes...${RESET}"
        sudo -u postgres psql -d ${POSTGRES_DB} -c "TRUNCATE TABLE \"Companies\" RESTART IDENTITY CASCADE;" 2>/dev/null || true
        sudo -u postgres psql -d ${POSTGRES_DB} -c "TRUNCATE TABLE \"Users\" RESTART IDENTITY CASCADE;" 2>/dev/null || true
        
        echo -e "${BLUE}🔄 Reintentando seeders...${RESET}"
        if ! npm run db:seed; then
            echo -e "${YELLOW}⚠️  Seeders fallaron definitivamente${RESET}"
            diagnose_database
            echo -e "${BLUE}ℹ️  Podrás crear datos manualmente desde la aplicación${RESET}"
        fi
    fi
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

# Configurar Nginx y SSL
setup_firewall
setup_nginx

# Verificar configuración inicial de Nginx (HTTP)
echo -e "${BLUE}🔍 Verificando configuración inicial de Nginx...${RESET}"
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo -e "${GREEN}✅ Nginx configurado correctamente (HTTP)${RESET}"
    
    # Configurar SSL con Certbot
    echo -e "${BLUE}🔒 Iniciando configuración SSL...${RESET}"
    setup_certbot
else
    echo -e "${RED}❌ Error en la configuración inicial de Nginx${RESET}"
    sudo nginx -t
    exit 1
fi

echo -e "${GREEN}🎉 ¡Configuración completa!${RESET}"
echo -e "${GREEN}🌐 Backend disponible en: https://${BACKEND_DOMAIN}${RESET}"
echo -e "${GREEN}🔒 SSL configurado automáticamente${RESET}"
echo -e "${GREEN}📝 Credenciales guardadas en: /root/back_credentials.txt${RESET}"
echo -e "${BLUE}📊 Estado de PM2:${RESET}"
pm2 status

echo -e "${BLUE}🔍 Estado de Nginx:${RESET}"
sudo systemctl status nginx --no-pager -l

echo -e "${BLUE}📋 Certificados SSL:${RESET}"
sudo certbot certificates 2>/dev/null || echo "No hay certificados configurados"