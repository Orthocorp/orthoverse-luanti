# The auth service: wallet sign-in, player names, and who owns which land.
# The same image runs the daily chain indexer (chain.js, the chain service).
# Build context: the repository root.
FROM node:24.22.1-bookworm-slim

WORKDIR /app
COPY web/auth/package.json web/auth/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund --loglevel=error
COPY web/auth/server.js web/auth/chain.js web/auth/names.js web/auth/metadata.js web/auth/classic.js web/auth/recovery-code.js web/auth/srp.js web/auth/check-accounts.js ./
COPY web/auth/classic /app/classic
COPY web/heraldry /app/heraldry
COPY mods/orthoverse_lands/data/lands.json /app/lands.json

# node:sqlite still prints an "experimental" warning on Node 24
ENV NODE_NO_WARNINGS=1
EXPOSE 8090
CMD ["node", "server.js"]
