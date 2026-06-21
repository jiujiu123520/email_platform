#!/bin/sh
# Nginx 启动脚本：处理环境变量替换并启动 Nginx

# 复制挂载的配置文件到工作目录
cp /etc/nginx/conf.d/default.conf /tmp/nginx.conf

# 替换环境变量
envsubst '${NGINX_PORT} ${DOMAIN} ${ENABLE_SSL}' < /tmp/nginx.conf > /etc/nginx/conf.d/default.conf

# 启动 Nginx（前台模式）
nginx -g 'daemon off;'
