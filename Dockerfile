FROM nginx:alpine

# 端口配置（与 EXPOSE、launch 命令 -e PORT 必须一致）
ENV PORT=8686

# 复制 Godot Web 导出产物（HTML + JS + WASM + PCK）
COPY build/web/ /usr/share/nginx/html/

# 复制 nginx 配置（含 COOP/COEP 跨域隔离头，Godot 4 多线程必需）
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8686

CMD ["nginx", "-g", "daemon off;"]
