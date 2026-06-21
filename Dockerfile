# ============================================================
# 邮件发送平台 - Dockerfile
# 使用国内 apt 源加速构建
# ============================================================
FROM python:3.9-slim

# 使用国内 apt 源（兼容 Debian 12 新格式）
RUN rm -f /etc/apt/sources.list.d/debian.sources 2>/dev/null; \
    echo 'deb http://mirrors.ustc.edu.cn/debian trixie main' > /etc/apt/sources.list && \
    echo 'deb http://mirrors.ustc.edu.cn/debian trixie-updates main' >> /etc/apt/sources.list && \
    echo 'deb http://mirrors.ustc.edu.cn/debian-security trixie-security main' >> /etc/apt/sources.list

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 复制项目文件
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 复制源码
COPY . .

# 暴露端口
EXPOSE 5000

# 启动命令 - 使用 wsgi.py 入口
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:5000", "wsgi:app"]
