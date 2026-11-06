# The auth service: wallet sign-in, player names, and who owns which land.
# Build context: the repository root.
FROM node:24.22.0-bookworm-slim

WORKDIR /app
COPY web/auth/package.json web/auth/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund --loglevel=error
COPY web/auth/server.js ./
COPY mods/orthoverse_lands/data/lands.json /app/lands.json

# node:sqlite still prints an "experimental" warning on Node 24
ENV NODE_NO_WARNINGS=1
EXPOSE 8090
CMD ["node", "server.js"]
