# Frappe Press 没有官方发布的镜像,这里参照 frappe_docker 官方生产 Containerfile 的结构
# 自己构建一份,关键差异点写在下面的注释里。
#
# 已验证的版本组合(写文件当天实测,如未来构建失败,先回退到这两个 commit 重试):
#   frappe (fork): https://github.com/balamurali27/frappe @ fc-ci   (commit 277cb95)
#   press:         https://github.com/frappe/press @ develop        (commit 02f45f6)
#
# 为什么不用标准 frappe/frappe(version-15/develop)?
#   实测过:press 的依赖(pyOpenSSL、cryptography、requests 等)与标准 frappe 分支的
#   依赖版本区间是硬冲突,不重叠。press 自己的 CI(.github/helper/install.sh)用的就是
#   上面这个 fork+分支组合,这是 press 团队自己在用、真实跑通的配方,不是标准 frappe。
#
# 已知限制(不影响"部署成功+站点能访问"这个验收标准,但功能上不完整):
#   - 没有装 Chromium,press 自带的网站截图功能(用 playwright/selenium)用不了
#   - 没有配置 AWS/DigitalOcean/Hetzner/OCI 凭证,真实的"创建云服务器"功能用不了
#   这两点本来就需要老师在 Press 的设置页面里填真实凭证才能用,不是部署阶段能解决的

ARG PYTHON_VERSION=3.10
ARG DEBIAN_BASE=bookworm
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base

ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm
ARG NODE_VERSION=22.13.0
ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    curl \
    git \
    vim \
    nginx \
    gettext-base \
    file \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libpangocairo-1.0-0 \
    restic \
    gpg \
    mariadb-client \
    less \
    libpq-dev \
    postgresql-client \
    wait-for-it \
    jq \
    media-types \
    && mkdir -p ${NVM_DIR} \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use v${NODE_VERSION} \
    && npm install -g yarn \
    && nvm alias default v${NODE_VERSION} \
    && rm -rf ${NVM_DIR}/.cache \
    && echo 'export NVM_DIR="/home/frappe/.nvm"' >>/home/frappe/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >>/home/frappe/.bashrc \
    && if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi \
    && if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi \
    && downloaded_file=wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb \
    && curl -sLO https://github.com/wkhtmltopdf/packaging/releases/download/$WKHTMLTOPDF_VERSION/$downloaded_file \
    && apt-get install -y ./$downloaded_file \
    && rm $downloaded_file \
    && rm -rf /var/lib/apt/lists/* \
    && rm -fr /etc/nginx/sites-enabled/default \
    && mkdir -p /etc/nginx/snippets \
    && pip3 install frappe-bench \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe /etc/nginx/conf.d \
    && chown -R frappe:frappe /etc/nginx/nginx.conf \
    && chown -R frappe:frappe /etc/nginx/snippets \
    && chown -R frappe:frappe /var/log/nginx \
    && chown -R frappe:frappe /var/lib/nginx \
    && chown -R frappe:frappe /run/nginx.pid

COPY resources/nginx-template.conf /templates/nginx/frappe.conf.template
COPY resources/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
COPY resources/security_headers.conf /etc/nginx/snippets/security_headers.conf
RUN chmod 755 /usr/local/bin/nginx-entrypoint.sh

FROM base AS build

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    wget \
    libpq-dev \
    libffi-dev \
    liblcms2-dev \
    libldap2-dev \
    libmariadb-dev \
    libsasl2-dev \
    libtiff5-dev \
    libwebp-dev \
    pkg-config \
    redis-tools \
    rlwrap \
    tk8.6-dev \
    cron \
    gcc \
    build-essential \
    libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

USER frappe

FROM build AS builder

# 关键:不用标准 frappe/frappe,用 press 官方 CI 实际验证过的 fork + 分支组合
ARG FRAPPE_PATH=https://github.com/miao-Q777/frappe
ARG FRAPPE_BRANCH=fc-ci
ARG PRESS_REPO=https://github.com/frappe/press
ARG PRESS_BRANCH=develop

RUN bench init \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-procfile \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    bench get-app --branch=${PRESS_BRANCH} ${PRESS_REPO} && \
    bench setup requirements && \
    bench build --app press && \
    echo "{}" > sites/common_site_config.json && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM base AS press

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets && \
    rm -rf /home/frappe/frappe-bench/sites/assets

VOLUME [ \
    "/home/frappe/frappe-bench/sites", \
    "/home/frappe/frappe-bench/logs" \
    ]

USER root
COPY resources/main-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

COPY resources/start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["start.sh"]
