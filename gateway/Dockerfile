ARG NODE_IMAGE
ARG CONCORDE_REPO
ARG CONCORDE_SHA
ARG KEYPER_AGENT_REPO
ARG KEYPER_AGENT_SHA

# Stage 1: Build the Concorde package tarball from the pinned upstream commit
FROM ${NODE_IMAGE} AS concorde
ARG CONCORDE_REPO
ARG CONCORDE_SHA
RUN apk add --no-cache git
WORKDIR /build/concorde
RUN git init \
    && git remote add origin "${CONCORDE_REPO}" \
    && git fetch --depth 1 origin "${CONCORDE_SHA}" \
    && git checkout FETCH_HEAD \
    && ACTUAL_SHA="$(git rev-parse HEAD)" \
    && if [ "${ACTUAL_SHA}" != "${CONCORDE_SHA}" ]; then \
         echo "Commit mismatch for Concorde: expected ${CONCORDE_SHA}, got ${ACTUAL_SHA}" >&2; \
         exit 1; \
       fi \
    && npm ci \
    && npm run build \
    && npm pack

# Stage 2: Fetch only telegram-channel/ from the pinned Keyper prototype commit
FROM ${NODE_IMAGE} AS telegram-channel
ARG KEYPER_AGENT_REPO
ARG KEYPER_AGENT_SHA
RUN apk add --no-cache git
WORKDIR /build/agent
RUN git init \
    && git remote add origin "${KEYPER_AGENT_REPO}" \
    && git fetch --depth 1 origin "${KEYPER_AGENT_SHA}" \
    && git checkout FETCH_HEAD \
    && ACTUAL_SHA="$(git rev-parse HEAD)" \
    && if [ "${ACTUAL_SHA}" != "${KEYPER_AGENT_SHA}" ]; then \
         echo "Commit mismatch for keyper agent: expected ${KEYPER_AGENT_SHA}, got ${ACTUAL_SHA}" >&2; \
         exit 1; \
       fi \
    && mkdir -p /out \
    && cp -r telegram-channel /out/

# Stage 3: Install gateway dependencies using the packed Concorde tarball
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY --from=concorde /build/concorde/shutter-network-concorde-0.1.0.tgz ./vendor/shutter-network-concorde-0.1.0.tgz
COPY package*.json ./
RUN npm install --no-audit --no-fund

# Stage 4: Gateway runtime image containing runtime code and channel module
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/vendor ./vendor
COPY package*.json ./
COPY tsconfig*.json ./
COPY drizzle.config*.ts ./
COPY --from=telegram-channel /out/telegram-channel ./telegram-channel
COPY src ./src
CMD ["node", "src/main.ts"]

# Stage 5: Target for running upstream Telegram channel test suite
FROM ${NODE_IMAGE} AS channel-tests
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/vendor ./vendor
COPY package*.json ./
COPY tsconfig*.json ./
COPY --from=telegram-channel /out/telegram-channel ./telegram-channel
CMD ["node", "--test", "telegram-channel/**/*.test.ts"]
