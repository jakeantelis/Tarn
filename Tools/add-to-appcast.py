#!/usr/bin/env python3
"""Adds a release to appcast.xml, newest first, for Sparkle.

Usage: add-to-appcast.py <version> <build> '<sign_update output>' <RELEASE_NOTES.md> [date]

The notes come from the "# Tarn <version>" section of the release notes file. Stops if the build number
is not higher than every build already in the feed, since Sparkle compares build numbers.
"""
import html, re, sys
from email.utils import format_datetime, parsedate_to_datetime
from datetime import datetime, timezone

FEED = "appcast.xml"
version, build, signature, notes_file = sys.argv[1:5]
date = datetime.fromisoformat(sys.argv[5].replace("Z", "+00:00")) if len(sys.argv) > 5 else datetime.now(timezone.utc)

feed = open(FEED, encoding="utf-8").read()
existing = [int(b) for b in re.findall(r"<sparkle:version>(\d+)</sparkle:version>", feed)]
if existing and int(build) <= max(existing):
    sys.exit(f"error: build {build} is not higher than {max(existing)} already in {FEED}. Raise CFBundleVersion.")

m = re.match(r'sparkle:edSignature="([^"]+)" length="(\d+)"', signature.strip())
if not m:
    sys.exit("error: expected the output of sign_update")
ed, length = m.groups()

# The section for this version: lines after "# Tarn <version>" (or "## Tarn <version>") up to the next heading.
lines, section, inside = open(notes_file, encoding="utf-8").read().splitlines(), [], False
for line in lines:
    if re.match(r"#+\s+Tarn\s+" + re.escape(version) + r"\s*$", line):
        inside = True
        continue
    if inside and line.startswith("#"):
        break
    if inside:
        section.append(line)
parts, bullets = [], []
for line in section + [""]:
    if line.startswith("- "):
        bullets.append(f"<li>{html.escape(line[2:].strip())}</li>")
        continue
    if bullets:
        parts.append("<ul>" + "".join(bullets) + "</ul>")
        bullets = []
    if line.strip():
        parts.append(f"<p>{html.escape(line.strip())}</p>")
description = "".join(parts) or f"<p>Tarn {html.escape(version)}</p>"

item = f"""    <item>
      <title>Tarn {html.escape(version)}</title>
      <pubDate>{format_datetime(date)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{description}]]></description>
      <enclosure url="https://github.com/jakeantelis/Tarn/releases/download/v{html.escape(version)}/Tarn.zip" sparkle:edSignature="{ed}" length="{length}" type="application/octet-stream"/>
    </item>
"""
marker = "    <item>" if "    <item>" in feed else "  </channel>"
feed = feed.replace(marker, item + marker, 1)
open(FEED, "w", encoding="utf-8").write(feed)
print(f"Added Tarn {version} (build {build}) to {FEED}")
