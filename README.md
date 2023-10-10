# Unbound DNS Server Docker Image

A fork of https://github.com/MatthewVance/unbound-docker, with customized features

* Compatible with recursive mode, use the sample config in `sample` folder
* `remote-control` can be toggled on/off by mounting a custom config file on `/opt/unbound/etc/unbound/unbound.conf.d`
* Still keeps the autoconfiguration of `rrset`, `msg-cache` and `slabs` from [MatthewVance's docker image](https://github.com/MatthewVance/unbound-docker)
* Compatible with OpenWRT's cgroups, `/sys/fs/cgroup/memory.max`

## Supported tags and respective `Dockerfile` links
- [`latest` (*Dockerfile*)](https://github.com/vincejv/unbound-docker/tree/main)

## What is Unbound?

Unbound is a validating, recursive, and caching DNS resolver.
> [unbound.net](https://unbound.net/)

## How to use this image

### Standard usage

Run this container with the following command:

```console
docker run \
--name=my-unbound \
--detach=true \
--publish=53:53/tcp \
--publish=53:53/udp \
--restart=unless-stopped \
vincejv/unbound:latest
```

### Docker Compose
Grab the sample `docker-compose.yml` file in `sample` directory
```yml
version: '3'
services:
  unbound:
    container_name: unbound
    image: vincejv/unbound:latest
    network_mode: host
    volumes:
      - type: bind
        read_only: true
        source: ./conf
        target: /opt/unbound/etc/unbound/unbound.conf.d
      - type: bind
        read_only: true
        source: ./forward-records.conf
        target: /opt/unbound/etc/unbound/forward-records.conf
      - type: bind
        read_only: true
        source: ./local-zone.conf
        target: /opt/unbound/etc/unbound/a-records.conf
    restart: unless-stopped
```