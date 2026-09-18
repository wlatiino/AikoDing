FROM ghcr.io/anomalyco/opencode:latest

RUN apk add --no-cache nodejs npm wget

RUN mkdir -p /opt/opencode-skills/find-skills \
    && wget -qO /opt/opencode-skills/find-skills/SKILL.md \
       https://raw.githubusercontent.com/vercel-labs/skills/main/skills/find-skills/SKILL.md \
    && mkdir -p /opt/opencode-skills/grill-me \
    && wget -qO /opt/opencode-skills/grill-me/SKILL.md \
       https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grill-me/SKILL.md \
    && mkdir -p /opt/opencode-skills/grilling \
    && wget -qO /opt/opencode-skills/grilling/SKILL.md \
       https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md

COPY entrypoint.sh /usr/local/bin/opencode-entrypoint
RUN chmod +x /usr/local/bin/opencode-entrypoint

ENTRYPOINT ["/usr/local/bin/opencode-entrypoint"]
CMD ["web", "--hostname", "0.0.0.0", "--port", "5001"]
