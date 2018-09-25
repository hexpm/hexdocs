FROM elixir:1.6.6-alpine as build

# install build dependencies
RUN apk add --update git

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

# build release
COPY priv priv
COPY lib lib
RUN mix compile
COPY rel rel
RUN mix release --no-tar

# prepare release image
FROM alpine:3.6 AS app
RUN apk add --update bash openssl

RUN mkdir /app && chown -R nobody: /app
WORKDIR /app
USER nobody

COPY --from=build /app/_build/prod/rel/hexdocs ./

ENV HOME=/app REPLACE_OS_VARS=true
