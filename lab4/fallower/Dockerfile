FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod main.go ./
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o kv-follower .

FROM alpine:latest
RUN apk --no-cache add ca-certificates

WORKDIR /root/
COPY --from=builder /app/kv-follower .

EXPOSE 8080
CMD ["./kv-follower"]
