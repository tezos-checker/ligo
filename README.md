# ligo
Patched version of Ligo used to compile Checker

Docker images are published to the GitHub container registry at: [ghcr.io/tezos-checker/ligo](https://github.com/tezos-checker/ligo/pkgs/container/ligo).

# Docker build

To build a Docker image containing this Ligo fork:

1. First, you'll need to obtain permissions to push new images, follow the guide to set up push access: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
  1. Note: To build multi-arch images, see the [docker buildx info](https://docs.docker.com/desktop/multi-arch/), as a little initial set-up may be necessary.
1. With those prerequisites out of the way, run:

```console
$ export IMAGE_TAG="x.y.z-checker"

$ touch changelog.txt
$ docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/tezos-checker/ligo:"$IMAGE_TAG" --push .

$ docker push
```
