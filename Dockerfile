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

ARG CODE_VERSION
ENV CODE_VERSION=$CODE_VERSION

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get
RUN mix deps.compile

# build release
COPY lib lib
RUN mix compile
COPY rel rel
RUN mix release --no-tar

# prepare release image
FROM alpine:3.6
RUN apk add --update bash

RUN mkdir /app && chown -R nobody: /app
WORKDIR /app
USER nobody

COPY --from=build /app/_build/prod/rel/hexdocs ./

ENV REPLACE_OS_VARS=true

ENTRYPOINT ["/app/bin/hexdocs", "foreground"]
