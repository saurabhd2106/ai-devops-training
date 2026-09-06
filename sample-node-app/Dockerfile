FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY app.js ./
COPY routes ./routes
COPY services ./services
COPY utils ./utils
EXPOSE 3000
ENV PORT=3000
CMD ["node", "app.js"]
