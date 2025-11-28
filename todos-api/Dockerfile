FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci 

COPY . .

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8082/todos 2>&1 | grep -q '401\|200' || exit 1

CMD ["node", "server.js"]