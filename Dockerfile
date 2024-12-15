FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS build

# install build dependencies
RUN apk add --no-cache --update git

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
FROM alpine:3.20.3 AS app
RUN apk add --no-cache --update bash openssl libgcc libstdc++ ncurses

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/hexdocs ./
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
