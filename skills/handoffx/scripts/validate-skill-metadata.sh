#!/bin/bash
# validate-skill-metadata.sh — validate SKILL.md frontmatter and metadata budget
# usage: validate-skill-metadata.sh [path]
set -e

ROOT="${1:-.}"
LIMIT="${SKILL_DESCRIPTION_LIMIT:-160}"

if [ ! -e "$ROOT" ]; then
    echo "❌ path not found: $ROOT" >&2
    exit 2
fi

ruby -ryaml -e '
root = ARGV.fetch(0)
limit = Integer(ARGV.fetch(1))
files = if File.file?(root)
  [root]
else
  Dir.glob(File.join(root, "**", "SKILL.md"), File::FNM_DOTMATCH)
end

bad = []
files.sort.each do |path|
  begin
    text = File.read(path)
    parts = text.split(/^---\s*$/, 3)
    raise "missing YAML frontmatter" unless parts.length >= 3
    data = YAML.safe_load(parts.fetch(1))
    name = data.fetch("name").to_s
    description = data.fetch("description").to_s
    raise "missing name" if name.empty?
    raise "missing description" if description.empty?
    if description.length > limit
      raise "description too long #{description.length}/#{limit}"
    end
  rescue => e
    bad << "#{path}: #{e.message}"
  end
end

if bad.empty?
  puts "✅ skill metadata OK: #{files.length} file(s), limit #{limit}"
else
  warn bad.join("\n")
  exit 1
end
' "$ROOT" "$LIMIT"
