# Stage 1: Build the release
FROM elixir:1.17.2 AS build

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set the working directory
WORKDIR /autopgo

# Copy the mix.exs and mix.lock files to the container
COPY mix.exs mix.lock ./

# Fetch and compile dependencies
RUN mix deps.get && mix deps.compile

# Copy the application code
COPY . .

# Build the release


RUN mix release

# Stage 2: Create the runtime image
FROM golang:1.22 AS runtime

# Install the necessary packages for setting the locale
RUN apt-get update && apt-get install -y locales

# Generate and set the locale to UTF-8
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8

# Set environment variables for the locale
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Set the ELIXIR_ERL_OPTIONS environment variable
ENV ELIXIR_ERL_OPTIONS="+fnu"

# Set the working directory
WORKDIR /autopgo

# Copy the release from the build stage
COPY --from=build /autopgo/_build/prod/rel/autopgo .
COPY --from=build /autopgo/handle_stdin.sh .
