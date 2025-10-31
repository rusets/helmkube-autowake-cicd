# Use a lightweight official Node.js 18 image based on Alpine Linux
FROM node:18-alpine

# Set working directory inside the container
WORKDIR /usr/src/app

# Copy only dependency manifests first to leverage Docker layer caching
COPY package.json package-lock.json* ./

# Install production dependencies:
# - Prefer reproducible installs with npm ci when lockfile exists
# - Fallback to npm install if lockfile is missing (e.g., first run)
RUN npm ci --omit=dev || npm install --omit=dev

# Copy the rest of the application source code
COPY . .

# Expose the application port (the app should listen on 3000)
EXPOSE 3000

# Default start command for the container
CMD ["npm","start"]