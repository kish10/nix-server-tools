# Docker service for paperless-ngx

## Troubleshooting

### Containers not starting properly.

If containers don't start properly such as not being connected to the `proxyNetwork` or get an error when connecting to the `redis` service, then:
- Run `docker container prune -a` (when the containers are not running), and start running the containers again.
