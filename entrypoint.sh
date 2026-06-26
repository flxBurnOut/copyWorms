#!/bin/sh
# 替换 nginx 配置中的端口，支持 CNB 预览模式的 PORT 环境变量
PORT=${PORT:-8080}
sed -i "s/__PORT__/${PORT}/g" /etc/nginx/conf.d/default.conf
echo "Starting nginx on port ${PORT}..."
exec nginx -g "daemon off;"
