# DeployFlow: a static website served by Nginx inside a Docker container.

# Small, official Nginx image built on Alpine Linux.
FROM nginx:alpine

LABEL org.opencontainers.image.title="DeployFlow" \
      org.opencontainers.image.description="Static DevOps site served by Nginx in a Docker container"

# Replace the stock server config with ours, which listens on port 8081.
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Replace Nginx's default welcome page with our site.
COPY app/index.html /usr/share/nginx/html/index.html

# Fail the build early if the Nginx configuration is invalid.
RUN nginx -t

# Nginx listens on port 8081 inside the container.
# At run time we publish it on the host as 8081 with: -p 8081:8081
EXPOSE 8081

# Lets `docker ps` report the container as healthy once Nginx answers on 8081.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8081/"]

# The base image already starts Nginx in the foreground:
# CMD ["nginx", "-g", "daemon off;"]
