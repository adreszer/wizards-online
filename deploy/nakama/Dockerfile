# Production Nakama image: the server modules and content are baked in, secrets
# come from the environment at start (start.sh). Built from the repo root by
# docker-compose.coolify.yml; see docs/deploy.md.
FROM registry.heroiclabs.com/heroiclabs/nakama:3.28.0
COPY nakama/modules /nakama/data/modules
COPY nakama/content /nakama/data/content
COPY deploy/nakama/school_rules.local.json /nakama/data/content/school_rules.local.json
COPY deploy/nakama/production.yml /nakama/data/production.yml
COPY deploy/nakama/start.sh /nakama/start.sh
ENTRYPOINT ["/bin/sh", "/nakama/start.sh"]
