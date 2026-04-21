# ── Stage 1: Build Flutter Web ────────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl git unzip xz-utils zip ca-certificates libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$PATH:${FLUTTER_HOME}/bin"

RUN git clone --depth 1 --branch stable \
    https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && flutter config --no-analytics \
    && flutter precache --web

WORKDIR /app

# Cache pub dependencies as a separate layer
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_ANON_KEY" ]; then \
      flutter build web --release \
        --dart-define=SUPABASE_URL="$SUPABASE_URL" \
        --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"; \
    else \
      flutter build web --release; \
    fi

# ── Stage 2: Serve with Nginx ─────────────────────────────────────────────────
FROM nginx:stable-alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
