FROM gcr.io/distroless/base
COPY ./build/aarch64/gsm /gsm
ENTRYPOINT ["/gsm"]
