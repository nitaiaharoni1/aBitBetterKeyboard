# Zero runtime dependencies, so the image needs nothing `npm install` would
# fetch — just the Node 22 runtime, for the built-in `fetch` this service
# calls Vertex with.
FROM node:22-slim

WORKDIR /app
COPY package.json ./
COPY server.js ./
COPY src ./src

ENV NODE_ENV=production
# Cloud Run injects its own $PORT at deploy time; 8080 only matters when
# running this image directly (`docker run -p 8080:8080 ...`).
ENV PORT=8080
EXPOSE 8080

CMD ["node", "server.js"]
