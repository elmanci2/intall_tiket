#!/bin/bash
set -e

# Colores para output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

echo -e "${GREEN}🔧 Script de reparación de Nginx${RESET}"

# Función para limpiar configuraciones problemáticas
cleanup_nginx_configs() {
    echo -e "${BLUE}🧹 Limpiando configuraciones problemáticas de Nginx...${RESET}"
    
    # Buscar archivos con problemas
    PROBLEMATIC_FILES=$(sudo find /etc/nginx/sites-enabled/ -name "*pyme*" 2>/dev/null || true)
    
    if [ ! -z "$PROBLEMATIC_FILES" ]; then
        echo -e "${YELLOW}📁 Archivos problemáticos encontrados:${RESET}"
        echo "$PROBLEMATIC_FILES"
        
        # Deshabilitar archivos problemáticos
        for file in $PROBLEMATIC_FILES; do
            echo -e "${YELLOW}🚫 Deshabilitando: $file${RESET}"
            sudo rm -f "$file"
        done
    fi
    
    # Verificar si hay referencias al formato de log "pyme"
    echo -e "${BLUE}🔍 Verificando referencias al formato de log 'pyme'...${RESET}"
    if sudo grep -r "access_log.*pyme" /etc/nginx/sites-enabled/ 2>/dev/null; then
        echo -e "${RED}❌ Se encontraron referencias al formato 'pyme'${RESET}"
        echo -e "${YELLOW}💡 Necesitamos definir este formato o eliminar las referencias${RESET}"
    fi
}

# Función para crear formato de log personalizado
create_custom_log_format() {
    echo -e "${BLUE}📝 Configurando formato de log personalizado...${RESET}"
    
    # Crear archivo de configuración para formatos de log personalizados
    sudo tee "/etc/nginx/conf.d/custom-log-formats.conf" > /dev/null <<'EOF'
# Formatos de log personalizados
log_format pyme '$remote_addr - $remote_user [$time_local] '
                '"$request" $status $body_bytes_sent '
                '"$http_referer" "$http_user_agent" '
                '$request_time $upstream_response_time';

log_format detailed '$remote_addr - $remote_user [$time_local] '
                   '"$request" $status $body_bytes_sent '
                   '"$http_referer" "$http_user_agent" '
                   '$request_time $upstream_response_time '
                   '$upstream_addr $upstream_status';
EOF
    
    echo -e "${GREEN}✅ Formato de log personalizado creado${RESET}"
}

# Función para verificar y reparar configuración principal
fix_main_nginx_config() {
    echo -e "${BLUE}🔧 Verificando configuración principal de Nginx...${RESET}"
    
    # Backup de la configuración actual
    if [ ! -f "/etc/nginx/nginx.conf.backup.$(date +%Y%m%d)" ]; then
        sudo cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.backup.$(date +%Y%m%d)"
        echo -e "${GREEN}💾 Backup creado: /etc/nginx/nginx.conf.backup.$(date +%Y%m%d)${RESET}"
    fi
    
    # Verificar que la configuración principal incluya los archivos conf.d
    if ! sudo grep -q "include /etc/nginx/conf.d/\*.conf;" /etc/nginx/nginx.conf; then
        echo -e "${YELLOW}🔧 Agregando inclusión de archivos conf.d...${RESET}"
        sudo sed -i '/include \/etc\/nginx\/sites-enabled\/\*/i\\tinclude /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
    fi
}

# Función para listar y revisar todas las configuraciones
review_all_configs() {
    echo -e "${BLUE}📋 Revisando todas las configuraciones activas...${RESET}"
    
    echo -e "${YELLOW}📁 Sitios habilitados:${RESET}"
    ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "No hay sitios habilitados"
    
    echo -e "${YELLOW}📁 Configuraciones adicionales:${RESET}"
    ls -la /etc/nginx/conf.d/ 2>/dev/null || echo "No hay configuraciones adicionales"
    
    echo -e "${YELLOW}🔍 Verificando sintaxis de cada archivo...${RESET}"
    for config_file in /etc/nginx/sites-enabled/*; do
        if [ -f "$config_file" ]; then
            echo -e "${BLUE}   Verificando: $(basename $config_file)${RESET}"
            if ! sudo nginx -t -c <(cat /etc/nginx/nginx.conf; echo "events {}"; echo "http { include $config_file; }") 2>/dev/null; then
                echo -e "${RED}   ❌ Problema en: $config_file${RESET}"
            else
                echo -e "${GREEN}   ✅ OK: $config_file${RESET}"
            fi
        fi
    done
}

# Función para crear configuración segura por defecto
create_safe_default_config() {
    echo -e "${BLUE}🛡️ Creando configuración segura por defecto...${RESET}"
    
    # Crear configuración básica y funcional
    sudo tee "/etc/nginx/sites-available/default-safe" > /dev/null <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    # Logs básicos
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Bloquear acceso a archivos ocultos
    location ~ /\. {
        deny all;
    }
}
EOF
    
    echo -e "${GREEN}✅ Configuración segura creada${RESET}"
}

# Función principal de reparación
main_repair() {
    echo -e "${GREEN}🚀 Iniciando reparación de Nginx...${RESET}"
    
    # Paso 1: Limpiar configuraciones problemáticas
    cleanup_nginx_configs
    
    # Paso 2: Crear formato de log personalizado
    create_custom_log_format
    
    # Paso 3: Reparar configuración principal
    fix_main_nginx_config
    
    # Paso 4: Crear configuración segura por defecto
    create_safe_default_config
    
    # Paso 5: Probar configuración
    echo -e "${BLUE}🧪 Probando configuración reparada...${RESET}"
    if sudo nginx -t; then
        echo -e "${GREEN}✅ Configuración de Nginx reparada exitosamente${RESET}"
        
        # Recargar Nginx
        echo -e "${BLUE}🔄 Recargando Nginx...${RESET}"
        sudo systemctl reload nginx
        echo -e "${GREEN}✅ Nginx recargado${RESET}"
        
        # Mostrar estado
        echo -e "${BLUE}📊 Estado de Nginx:${RESET}"
        sudo systemctl status nginx --no-pager -l
        
    else
        echo -e "${RED}❌ Aún hay problemas en la configuración${RESET}"
        echo -e "${YELLOW}🔍 Revisando configuraciones individuales...${RESET}"
        review_all_configs
        return 1
    fi
    
    # Paso 6: Revisar configuraciones finales
    review_all_configs
}

# Función para restaurar desde backup si es necesario
restore_from_backup() {
    echo -e "${YELLOW}🔙 ¿Deseas restaurar desde un backup? (y/N)${RESET}"
    read -p "Respuesta: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BACKUP_FILES=$(ls /etc/nginx/nginx.conf.backup.* 2>/dev/null || true)
        if [ ! -z "$BACKUP_FILES" ]; then
            echo -e "${BLUE}📁 Backups disponibles:${RESET}"
            ls -la /etc/nginx/nginx.conf.backup.*
            echo -e "${YELLOW}Ingresa el nombre completo del backup a restaurar:${RESET}"
            read BACKUP_FILE
            if [ -f "$BACKUP_FILE" ]; then
                sudo cp "$BACKUP_FILE" /etc/nginx/nginx.conf
                echo -e "${GREEN}✅ Backup restaurado${RESET}"
            else
                echo -e "${RED}❌ Archivo de backup no encontrado${RESET}"
            fi
        else
            echo -e "${YELLOW}⚠️ No se encontraron backups${RESET}"
        fi
    fi
}

# Función para mostrar diagnóstico completo
show_diagnosis() {
    echo -e "${BLUE}🔍 Diagnóstico completo de Nginx${RESET}"
    echo -e "${BLUE}================================${RESET}"
    
    echo -e "${YELLOW}📁 Estructura de directorios:${RESET}"
    sudo ls -la /etc/nginx/
    
    echo -e "${YELLOW}🔧 Configuración principal:${RESET}"
    sudo head -20 /etc/nginx/nginx.conf
    
    echo -e "${YELLOW}🌐 Sitios disponibles:${RESET}"
    sudo ls -la /etc/nginx/sites-available/ 2>/dev/null || echo "Directorio vacío"
    
    echo -e "${YELLOW}✅ Sitios habilitados:${RESET}"
    sudo ls -la /etc/nginx/sites-enabled/ 2>/dev/null || echo "Directorio vacío"
    
    echo -e "${YELLOW}⚙️ Configuraciones adicionales:${RESET}"
    sudo ls -la /etc/nginx/conf.d/ 2>/dev/null || echo "Directorio vacío"
    
    echo -e "${YELLOW}📝 Logs recientes:${RESET}"
    sudo tail -10 /var/log/nginx/error.log 2>/dev/null || echo "No hay logs de error"
    
    echo -e "${YELLOW}🔍 Proceso de Nginx:${RESET}"
    ps aux | grep nginx || echo "Nginx no está ejecutándose"
}

# Menú principal
echo -e "${BLUE}¿Qué acción deseas realizar?${RESET}"
echo "1) Reparación automática completa"
echo "2) Solo limpiar configuraciones problemáticas"
echo "3) Mostrar diagnóstico completo"
echo "4) Restaurar desde backup"
echo "5) Salir"

read -p "Selecciona una opción (1-5): " OPTION

case $OPTION in
    1)
        main_repair
        ;;
    2)
        cleanup_nginx_configs
        sudo nginx -t && sudo systemctl reload nginx
        ;;
    3)
        show_diagnosis
        ;;
    4)
        restore_from_backup
        ;;
    5)
        echo -e "${GREEN}👋 ¡Hasta luego!${RESET}"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Opción no válida${RESET}"
        exit 1
        ;;
esac

echo -e "${GREEN}🎉 ¡Proceso completado!${RESET}"