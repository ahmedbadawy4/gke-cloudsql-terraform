# Build stage: compile the TypeScript and keep only production dependencies.
FROM node:24-alpine AS build
WORKDIR /app
COPY application/package.json application/package-lock.json application/tsconfig.json ./
RUN npm ci
COPY application/ ./
RUN npm run build && npm prune --omit=dev

# Runtime stage: no compiler, no dev dependencies, runs as the unprivileged node user.
FROM node:24-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/build ./build
USER node
EXPOSE 3000
CMD ["node", "build/index.js"]
