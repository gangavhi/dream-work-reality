FROM rust:1.95 AS builder
WORKDIR /app

COPY . .
RUN cargo build -p core_api --release

FROM debian:bookworm-slim
RUN useradd -m appuser
WORKDIR /home/appuser
COPY --from=builder /app/target/release/core_api /usr/local/bin/core_api
USER appuser
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/core_api"]
