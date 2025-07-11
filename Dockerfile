ARG ELIXIR_VERSION=1.18.1
ARG ERLANG_VERSION=27.2
ARG DEBIAN_VERSION=bookworm-20241223-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# prepare build dir
RUN mkdir /app
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get
RUN mix deps.compile

# build project
COPY priv priv
COPY lib lib
RUN mix compile

# build release
COPY rel rel
RUN mix do sentry.package_source_code, release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update && \
    apt upgrade -y && \
    apt install --no-install-recommends -y \
      bash openssl ca-certificates && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/hexdocs ./
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
ENV LANG=C.UTF-8
