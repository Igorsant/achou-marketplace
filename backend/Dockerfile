FROM node:24-alpine AS development
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY prisma ./prisma
RUN npx prisma generate
COPY . .
EXPOSE 3000
CMD ["npm", "run", "start:dev"]

FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY prisma ./prisma
RUN npx prisma generate
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:24-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
# Usuario sem privilegio (uid 1000, ja existe na imagem node). Os arquivos
# ficam do root: o processo le, mas nao altera o proprio codigo.
USER node
EXPOSE 3000
CMD ["node", "dist/main"]

# Imagem do Job de migration. O estagio production nao serve: o `npm prune`
# remove o CLI do Prisma, que e devDependency. Aqui entra so o CLI, na versao
# travada no package-lock -- a imagem existe para rodar um comando.
FROM node:24-alpine AS migrate
WORKDIR /app
COPY package-lock.json ./
RUN npm install --no-save --no-package-lock \
      prisma@"$(node -p "require('./package-lock.json').packages['node_modules/prisma'].version")" \
    && rm package-lock.json && npm cache clean --force
COPY prisma ./prisma
USER node
# Binario direto, sem npx: o npx checa atualizacao do npm e polui o log do Job.
CMD ["node_modules/.bin/prisma", "migrate", "deploy"]
