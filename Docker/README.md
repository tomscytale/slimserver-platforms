# logitechmediaserver

The [LMS Community](https://github.com/LMS-Community)'s Docker image for [Logitech Media Server](https://github.com/Logitech/slimserver/)

## Tags

* `latest`: the latest release version, currently v8.1.1
* `stable`: the [bug fix branch](https://github.com/Logitech/slimserver/tree/public/8.1) based on the latest release, currently v8.1.2
* `dev`: the [development version](https://github.com/Logitech/slimserver/), with new features, and potentially less stability, currently v8.2.0

## Installation

Run:

```
docker run -it \
      -v "<somewhere>":"/config":rw \
      -v "<somewhere>":"/music":ro \
      -v "<somewhere>":"/playlist":rw \
      -v "/etc/localtime":"/etc/localtime":ro \
      -v "/etc/timezone":"/etc/timezone":ro \
      -p 9000:9000/tcp \
      -p 9090:9090/tcp \
      -p 3483:3483/tcp \
      -p 3483:3483/udp \
      lmscommunity/logitechmediaserver
```

Please note that the http port always has to be a 1:1 mapping. You can't do just map it like `-p 9002:9000`, as Logitech Media Server is telling players on which port to connect. Therefore if you have to use a different http port for LMS (other than 9000) you'll have to set the `HTTP_PORT` environment variable, too:

```
docker run -it \
      -v "<somewhere>":"/config":rw \
      -v "<somewhere>":"/music":ro \
      -v "<somewhere>":"/playlist":rw \
      -v "/etc/localtime":"/etc/localtime":ro \
      -v "/etc/timezone":"/etc/timezone":ro \
      -p 9002:9002/tcp \
      -p 9090:9090/tcp \
      -p 3483:3483/tcp \
      -p 3483:3483/udp \
      -e HTTP_PORT=9002 \
      lmscommunity/logitechmediaserver
```

Docker compose:
```
version: '3'
services:
  lms:
    container_name: lms
    image: lmscommunity/logitechmediaserver
    volumes:
      - /<somewhere>:/config:rw
      - /<somewhere>:/music:ro
      - /<somewhere>:/playlist:rw
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
      - 3483:3483/tcp
      - 3483:3483/udp
    restart: always
```

Alternatively you can specify the user and group id to use:
For run add:
```
  -e PUID=1000 \
  -e PGID=1000
 ```
For compose add:
```
environment:
  - PUID=1000
  - PGID=1000
 ```