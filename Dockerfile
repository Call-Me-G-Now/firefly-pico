ARG REGISTRY=docker.io/stsdockerhub
ARG LARAVEL_ALPINE_VERSION=8.3.2-laravel-alpine3.19
ARG TARGETPLATFORM=linux/armv7

FROM --platform=$BUILDPLATFORM php:8.2-fpm as base
# RUN apt-get update && apt-get install -y \
# 		libfreetype-dev \
# 		libjpeg62-turbo-dev \
# 		libpng-dev \
# 	&& docker-php-ext-configure gd --with-freetype --with-jpeg \
# 	&& docker-php-ext-install -j$(nproc) gd

RUN docker-php-ext-install mysqli pdo pdo_mysql && docker-php-ext-enable pdo_mysql
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
RUN php composer-setup.php --install-dir /usr/local/bin/ --filename composer
RUN php -r "unlink('composer-setup.php');"

# RUN echo -e ${PATH}
RUN ls -lahrt /usr/local/bin/composer

FROM base as build-container
RUN apt-get update
RUN apt-get install git -y

WORKDIR /var/www/html

COPY back .

COPY back/.env.example .env

ENV COMPOSER_ALLOW_SUPERUSER=1

RUN composer install --no-dev
RUN php artisan key:generate

RUN tar --owner=www-data --group=www-data --exclude=.git -czf /tmp/app-back.tar.gz .

# # ================================

WORKDIR /var/www/html/front

COPY front .

ENV NODE_MAJOR=20

RUN apt-get install ca-certificates curl gnupg -y \
    && mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
run apt update \
    && apt install nodejs -y


RUN npm install
RUN npm run build

RUN npm cache clean --force

RUN tar --owner=www-data --group=www-data \
    --exclude=.git \
    --exclude=.nuxt \
    --exclude=.cache \
    --exclude=node_modules/eslint-plugin-vue \
    --exclude=node_modules/esbuild \
    --exclude=node_modules/date-fns \
    --exclude=node_modules/csso \
    --exclude=node_modules/node-gyp \
    --exclude=node_modules/vite \
    --exclude=node_modules/@npmcli \
    --exclude=node_modules/caniuse-lite \
    --exclude=node_modules/vite-plugin-inspect \
    --exclude=node_modules/@eslint \
    --exclude=node_modules/lodash \
    --exclude=node_modules/nuxi \
    --exclude=node_modules/@unocss \
    --exclude=node_modules/eslint* \
    --exclude=node_modules/@rollup \
    --exclude=node_modules/prettier \
    --exclude=node_modules/@esbuild \
    --exclude=node_modules/workbox-build \
    --exclude=node_modules/es-abstract \
    --exclude=node_modules/shiki \
    --exclude=node_modules/@nuxt \
    --exclude=node_modules/@typescript-eslint \
    --exclude=node_modules/@vue/devtools* \
    --exclude=node_modules/vant \
    --exclude=node_modules/mathjs \
    --exclude=node_modules/typescript \
    --exclude=node_modules/@faker-js \
    --exclude=node_modules/@opentelemetry \
    node_modules/@babel/parser \
    --exclude=node_modules/@babel \
    --exclude=node_modules/@tabler \
    -czf /tmp/app-front.tar.gz .
# ================================

FROM base

WORKDIR /var/www/html
RUN --mount=type=bind,from=build-container,source=/tmp/,target=/build \
    tar -xf /build/app-back.tar.gz -C .

WORKDIR /var/www/html/front
RUN --mount=type=bind,from=build-container,source=/tmp/,target=/build \
    tar -xf /build/app-front.tar.gz -C .

COPY docker/conf/supervisor/node.ini /etc/supervisor.d
COPY docker/conf/nginx/default.conf /etc/nginx/http.d

# Configure entrypoint
COPY docker/docker-entrypoint.d /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/*