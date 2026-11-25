# Build stage: compile the TypeScript and keep only production dependencies.
FROM node:26-alpine AS build
WORKDIR /app
COPY application/package.json application/package-lock.json application/tsconfig.json ./
RUN npm ci
COPY application/ ./
RUN npm run build && npm prune --omit=dev

# Runtime stage: no compiler, no dev dependencies, runs as the unprivileged node
# user. The user id is numeric (1000 is the node user) so that Kubernetes can
# check runAsNonRoot, which it cannot do for a user name.
FROM node:26-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/build ./build
USER 1000:1000
EXPOSE 3000
CMD ["node", "build/index.js"]
