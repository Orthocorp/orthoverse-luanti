# Nightly backups of the world, sign-ins and chain index (docker/backup/backup.js).
# Build context: the repository root. Nothing but Node's own modules.
FROM node:24.22.1-bookworm-slim

WORKDIR /app
COPY docker/backup/backup.js ./
# node:sqlite still prints an "experimental" warning on Node 24
ENV NODE_NO_WARNINGS=1
CMD ["node", "/app/backup.js"]
