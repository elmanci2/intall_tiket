#!/bin/bash
set -e

# Colores para output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

FRONT_DIR="$1"

echo -e "${GREEN}🎨 Configuración inicial del frontend${RESET}"
echo -e "${BLUE}📁 Directorio frontend: $FRONT_DIR${RESET}"

# Verificar que el directorio existe
if [ ! -d "$FRONT_DIR" ]; then
    echo -e "${RED}❌ Error: El directorio $FRONT_DIR no existe${RESET}"
    exit 1
fi

# Verificar que existe package.json
if [ ! -f "$FRONT_DIR/package.json" ]; then
    echo -e "${RED}❌ Error: No se encontró package.json en $FRONT_DIR${RESET}"
    exit 1
fi

# Solicitar información del usuario
read -p "🔤 Nombre del sitio (ej: miapp): " NAME
read -p "🌐 URL del backend (ej: https://api.midominio.com): " BACKEND_URL
read -p "🌍 Dominio del frontend (ej: app.midominio.com): " FRONTEND_DOMAIN
read -p "📧 Email para Certbot/Let's Encrypt: " CERTBOT_EMAIL
read -p "🔐 Usuario admin: " ADMIN_USER
read -s -p "🔑 Contraseña admin: " ADMIN_PASS
echo
read -p "📦 Puerto interno del frontend (ej: 3001): " PORT

# Función para configurar Nginx para frontend
setup_nginx_frontend() {
    echo -e "${BLUE}🌐 Configurando Nginx para frontend...${RESET}"
    
    # Instalar Nginx si no está instalado
    if ! command -v nginx &>/dev/null; then
        echo -e "${GREEN}📦 Instalando Nginx...${RESET}"
        sudo apt update
        sudo apt install -y nginx
        sudo systemctl enable nginx
    else
        echo -e "${GREEN}✅ Nginx ya está instalado${RESET}"
    fi
    
    # Crear configuración de Nginx para el frontend
    sudo tee "/etc/nginx/sites-available/${NAME}-frontend" > /dev/null <<EOF
server {
    listen 80;
    server_name ${FRONTEND_DOMAIN};
    
    # Redirigir HTTP a HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FRONTEND_DOMAIN};
    
    # Certificados SSL (se configurarán con Certbot)
    ssl_certificate /etc/letsencrypt/live/${FRONTEND_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FRONTEND_DOMAIN}/privkey.pem;
    
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
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()";
    
    # Compresión Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        image/svg+xml;
    
    # Configuración del proxy al frontend
    location / {
        proxy_pass http://localhost:${PORT};
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
    
    # Configuración para archivos estáticos (si se sirven directamente)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        proxy_pass http://localhost:${PORT};
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff;
    }
    
    # Configuración para WebSockets (React Hot Reload en desarrollo)
    location /sockjs-node/ {
        proxy_pass http://localhost:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Logs específicos para el frontend
    access_log /var/log/nginx/${NAME}-frontend.access.log;
    error_log /var/log/nginx/${NAME}-frontend.error.log;
}
EOF
    
    # Habilitar el sitio
    sudo ln -sf "/etc/nginx/sites-available/${NAME}-frontend" "/etc/nginx/sites-enabled/"
    
    echo -e "${GREEN}✅ Configuración de Nginx para frontend creada${RESET}"
}

# Función para configurar Certbot y SSL para frontend
setup_certbot_frontend() {
    echo -e "${BLUE}🔒 Configurando Certbot y SSL para frontend...${RESET}"
    
    # Instalar Certbot si no está instalado
    if ! command -v certbot &>/dev/null; then
        echo -e "${GREEN}📦 Instalando Certbot...${RESET}"
        sudo apt update
        sudo apt install -y certbot python3-certbot-nginx
    else
        echo -e "${GREEN}✅ Certbot ya está instalado${RESET}"
    fi
    
    # Verificar que el dominio resuelve a esta IP
    echo -e "${YELLOW}🔍 Verificando resolución DNS para ${FRONTEND_DOMAIN}...${RESET}"
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "No se pudo obtener IP")
    DOMAIN_IP=$(dig +short ${FRONTEND_DOMAIN} 2>/dev/null || echo "No resuelve")
    
    echo -e "${BLUE}📍 IP del servidor: ${SERVER_IP}${RESET}"
    echo -e "${BLUE}📍 IP del dominio: ${DOMAIN_IP}${RESET}"
    
    if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
        echo -e "${YELLOW}⚠️  ADVERTENCIA: El dominio no apunta a este servidor${RESET}"
        echo -e "${YELLOW}   Asegúrate de que ${FRONTEND_DOMAIN} apunte a ${SERVER_IP}${RESET}"
        read -p "¿Continuar de todas formas? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ Configuración SSL cancelada${RESET}"
            return 1
        fi
    fi
    
    # Configuración temporal de Nginx sin SSL para validación
    sudo tee "/etc/nginx/sites-available/${NAME}-frontend-temp" > /dev/null <<EOF
server {
    listen 80;
    server_name ${FRONTEND_DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        proxy_pass http://localhost:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Activar configuración temporal
    sudo ln -sf "/etc/nginx/sites-available/${NAME}-frontend-temp" "/etc/nginx/sites-enabled/${NAME}-frontend"
    sudo nginx -t && sudo systemctl reload nginx
    
    # Obtener certificado SSL
    echo -e "${GREEN}🔐 Obteniendo certificado SSL...${RESET}"
    if sudo certbot certonly --nginx \
        --email "$CERTBOT_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$FRONTEND_DOMAIN" \
        --non-interactive; then
        
        echo -e "${GREEN}✅ Certificado SSL obtenido exitosamente${RESET}"
        
        # Activar configuración SSL completa
        sudo ln -sf "/etc/nginx/sites-available/${NAME}-frontend" "/etc/nginx/sites-enabled/"
        
        # Verificar configuración y recargar
        if sudo nginx -t; then
            sudo systemctl reload nginx
            echo -e "${GREEN}✅ Nginx recargado con configuración SSL${RESET}"
        else
            echo -e "${RED}❌ Error en la configuración de Nginx${RESET}"
            return 1
        fi
        
        # Configurar renovación automática si no existe
        if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
            echo -e "${BLUE}⏰ Configurando renovación automática de certificados...${RESET}"
            (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet --nginx && /usr/bin/systemctl reload nginx") | sudo crontab -
        fi
        
    else
        echo -e "${RED}❌ Error obteniendo certificado SSL${RESET}"
        echo -e "${YELLOW}🔧 Manteniendo configuración HTTP temporal${RESET}"
        return 1
    fi
}

# Función para configurar firewall (si no está configurado)
setup_firewall() {
    echo -e "${BLUE}🔥 Verificando configuración de firewall...${RESET}"
    
    if command -v ufw &>/dev/null; then
        # Permitir puertos necesarios
        sudo ufw allow ssh 2>/dev/null || true
        sudo ufw allow 80/tcp 2>/dev/null || true
        sudo ufw allow 443/tcp 2>/dev/null || true
        
        # Mostrar estado
        echo -e "${GREEN}✅ Firewall verificado${RESET}"
        sudo ufw status numbered
    else
        echo -e "${YELLOW}⚠️  UFW no está instalado${RESET}"
    fi
}

# Guardar credenciales
echo -e "${BLUE}💾 Guardando credenciales...${RESET}"
CRED_FILE="$HOME/${NAME}_frontend_credentials.txt"
cat > "$CRED_FILE" <<EOF
NAME=${NAME}
FRONTEND_DOMAIN=${FRONTEND_DOMAIN}
BACKEND_URL=${BACKEND_URL}
CERTBOT_EMAIL=${CERTBOT_EMAIL}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASS=${ADMIN_PASS}
PORT=${PORT}
FECHA_INSTALACION=$(date)
EOF

echo -e "${GREEN}📝 Credenciales guardadas en $CRED_FILE${RESET}"

# Instalar Bun si no existe
if ! command -v bun &> /dev/null; then
    echo -e "${GREEN}🍞 Instalando Bun...${RESET}"
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
    # Agregar a bashrc para futuras sesiones
    echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
else
    echo -e "${GREEN}✅ Bun ya está instalado${RESET}"
fi

# Cargar Bun para esta sesión
export PATH="$HOME/.bun/bin:$PATH"

cd "$FRONT_DIR"

echo -e "${BLUE}📦 Instalando dependencias...${RESET}"
if ! bun install; then
    echo -e "${YELLOW}⚠️  Bun falló, intentando con npm...${RESET}"
    npm install || {
        echo -e "${RED}❌ Error instalando dependencias${RESET}"
        exit 1
    }
fi

echo -e "${BLUE}📝 Configurando .env...${RESET}"
cat > .env <<EOF
REACT_APP_BACKEND_URL=${BACKEND_URL}
REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24
REACT_APP_FRONTEND_URL=https://${FRONTEND_DOMAIN}
GENERATE_SOURCEMAP=false
EOF

echo -e "${BLUE}🔨 Compilando aplicación...${RESET}"
if command -v bun &>/dev/null; then
    bun run build
else
    npm run build
fi

# Verificar que se creó el build
if [ ! -d "build" ]; then
    echo -e "${RED}❌ Error: No se generó la carpeta build${RESET}"
    exit 1
fi

echo -e "${BLUE}🌐 Creando servidor Express optimizado...${RESET}"
cat > server.js <<EOF
const express = require('express');
const path = require('path');
const compression = require('compression');
const helmet = require('helmet');

const app = express();

// Middleware de seguridad
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
            fontSrc: ["'self'", "https://fonts.gstatic.com"],
            imgSrc: ["'self'", "data:", "https:"],
            scriptSrc: ["'self'"],
            connectSrc: ["'self'", "${BACKEND_URL}"]
        }
    }
}));

// Compresión gzip
app.use(compression());

// Servir archivos estáticos con caché
app.use(express.static(path.join(__dirname, 'build'), {
    maxAge: '1y',
    etag: false
}));

// Manejar rutas de React Router
app.get('/*', (req, res) => {
    res.sendFile(path.join(__dirname, 'build', 'index.html'));
});

// Manejo de errores
app.use((err, req, res, next) => {
    console.error('Error del servidor:', err);
    res.status(500).send('Error interno del servidor');
});

const PORT = ${PORT};
app.listen(PORT, '127.0.0.1', () => {
    console.log(\`✅ Frontend corriendo en puerto \${PORT}\`);
    console.log(\`🌐 Disponible en: https://${FRONTEND_DOMAIN}\`);
});
EOF

echo -e "${BLUE}📦 Instalando dependencias del servidor...${RESET}"
cat > package-server.json <<EOF
{
    "name": "${NAME}-frontend-server",
    "version": "1.0.0",
    "dependencies": {
        "express": "^4.18.2",
        "compression": "^1.7.4",
        "helmet": "^7.0.0"
    }
}
EOF

npm install express compression helmet


echo -e "${BLUE}🚀 Iniciando con PM2...${RESET}"

# Detener proceso existente si existe
pm2 delete "${NAME}-frontend" 2>/dev/null || true

# Iniciar el nuevo proceso
if ! pm2 start server.js --name "${NAME}-frontend"; then
    echo -e "${RED}❌ Error iniciando con PM2${RESET}"
    exit 1
fi

pm2 save

echo -e "${GREEN}✅ Frontend iniciado exitosamente${RESET}"

# Configurar Nginx y SSL
setup_firewall
setup_nginx_frontend

# Verificar configuración de Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo -e "${GREEN}✅ Nginx configurado correctamente${RESET}"
    
    # Configurar SSL con Certbot
    setup_certbot_frontend
else
    echo -e "${RED}❌ Error en la configuración de Nginx${RESET}"
    exit 1
fi

echo -e "${GREEN}🎉 ¡Configuración del frontend completa!${RESET}"
echo -e "${GREEN}🌐 Frontend disponible en: https://${FRONTEND_DOMAIN}${RESET}"
echo -e "${GREEN}🔗 Backend conectado a: ${BACKEND_URL}${RESET}"
echo -e "${GREEN}🔒 SSL configurado automáticamente${RESET}"
echo -e "${GREEN}📝 Credenciales guardadas en: $CRED_FILE${RESET}"

echo -e "${BLUE}📊 Estado de PM2:${RESET}"
pm2 status

echo -e "${BLUE}🔍 Estado de Nginx:${RESET}"
sudo systemctl status nginx --no-pager -l

echo -e "${BLUE}📋 Certificados SSL:${RESET}"
sudo certbot certificates 2>/dev/null || echo "Verificando certificados..."

echo -e "${BLUE}🔧 Información de acceso:${RESET}"
echo -e "${GREEN}   👤 Usuario admin: ${ADMIN_USER}${RESET}"
echo -e "${GREEN}   🔑 Contraseña: [guardada en ${CRED_FILE}]${RESET}"