# The web proxy: browser players' WebSocket to the game server's UDP.
# Build context: the repository root.
FROM node:24.22.0-bookworm-slim

WORKDIR /app
COPY web/proxy/package.json web/proxy/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund --loglevel=error
COPY web/proxy/proxy.js ./

USER node
EXPOSE 8737
CMD ["node", "proxy.js"]
