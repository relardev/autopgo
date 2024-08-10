FROM autopgo

COPY . /code

ENV AUTOPGO_CONFIG=/code/

WORKDIR /code

RUN go build -o app

WORKDIR /autopgo

CMD ["./bin/autopgo", "start"]
