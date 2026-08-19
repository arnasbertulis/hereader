# The compiled Flutter web bundle, baked into the Caddy image that serves it.
#
# The build itself is not here. Flutter's SDK image would have to be pulled
# and the whole toolchain warmed for a build CI already runs on every push,
# so the workflow runs `flutter build web` on the runner and hands the
# output directory in as this file's context — which is why the context is
# `app/build/web` and not `app`, and why there is a single COPY below.
#
# Baking the bundle rather than mounting it from the host is what makes a
# web deploy atomic: the files change when the container is replaced, so
# there is no window where a request can be served half of one release and
# half of the next. It also means the release that is running can be named
# by an image tag, which a directory of copied files cannot be.
#
# The Caddyfile is deliberately still a bind mount in compose.yaml. Serving
# config changes far more often than it changes together with the bundle,
# and mounting it keeps `docker compose restart caddy` as the way to apply
# one.
FROM caddy:2

COPY . /srv/web
