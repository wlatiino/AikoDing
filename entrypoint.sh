#!/bin/sh
set -e

SKILLS_DIR="/root/.config/opencode/skills"
for skill in find-skills grill-me grilling; do
  mkdir -p "$SKILLS_DIR/$skill"
  cp "/opt/opencode-skills/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
done

# exec opencode "$@"
exec "$@"