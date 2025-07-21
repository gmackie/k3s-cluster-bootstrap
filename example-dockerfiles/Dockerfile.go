# Multi-stage Dockerfile for Go apps
# Produces tiny ~10MB images

# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Production stage
FROM scratch
WORKDIR /

# Copy the binary
COPY --from=builder /app/main .

# Copy SSL certificates for HTTPS calls
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080

CMD ["./main"]