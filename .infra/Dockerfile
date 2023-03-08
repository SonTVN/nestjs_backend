FROM node:16-bullseye-slim

RUN mkdir /app
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY ./backend/package.json ./backend/package-lock.json /app/
RUN npm install

# Copy source code
COPY ./backend /app/

# cat env
RUN cat .env

# Generate prisma
RUN npx prisma generate

# Build production
RUN npm run build

# Run app in port 3000
EXPOSE 3000
CMD node dist/main.js
