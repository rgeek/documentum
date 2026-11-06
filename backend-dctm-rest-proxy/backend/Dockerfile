# Documentum proxy backend — small Node image, no build step required.
FROM node:20-alpine AS runtime
WORKDIR /app

# Install deps first so Docker caches the layer when only server.js changes.
COPY package*.json ./
RUN npm ci --omit=dev

# Copy app source (server.js + nothing else).
COPY server.js ./

# Non-root user (security best-practice).
RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 4000
CMD ["node", "server.js"]
