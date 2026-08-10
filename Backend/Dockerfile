# **This image used to install nothing, and the comment saying so outlived the
# fact by four dependencies.** Verifying an App Attest attestation needs
# `@peculiar/x509` to walk Apple's chain, `cbor-x` to decode the attestation
# object, `jose` to sign session tokens and `reflect-metadata` underneath
# x509 — none of which are built into Node. With no install step the image
# built and pushed perfectly happily and then died on its first import:
#
#     Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'reflect-metadata'
#     imported from /app/src/attestationVerifier.js
#
# Cloud Run reports that as "container failed to start and listen on port
# 8080", which reads like a port problem and is not one. `npm ci` rather than
# `npm install` so the build fails loudly when the lockfile and package.json
# disagree, instead of quietly resolving a version nobody tested.
FROM node:22-slim

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.js ./
COPY src ./src

ENV NODE_ENV=production
# Cloud Run injects its own $PORT at deploy time; 8080 only matters when
# running this image directly (`docker run -p 8080:8080 ...`).
ENV PORT=8080
EXPOSE 8080

CMD ["node", "server.js"]
