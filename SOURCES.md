# Audio sources

Every sound shipped in Stillwater must be CC0 or self recorded. Record each file here before it is committed.

Files go in `Resources/Sounds/`, named after the soundscape. A bundled file replaces the built in synthesized version of that sound (wind is still synthesized). `Tools/make-loop.sh` cuts each source into a seamless loop: it crossfades the end into the start, sets a steady level and encodes AAC. The original downloads are not kept in the repo.

All files below come from BigSoundBank (https://bigsoundbank.com), released under CC0 (public domain). The license wording was read on each sound's own page on 2026-10-30. Attribution is not required but is appreciated, so credit is given here.

| App file | Source title | Sound no. | Author | License | URL | Loop cut |
|----------|--------------|-----------|--------|---------|-----|----------|
| ocean.m4a | Sea: Waves | s0266 | DenisChardonnet | CC0 | https://bigsoundbank.com/sea-waves-s0266.html | 1s to 56s, 50s loop |
| rain.m4a | Rain Under an Umbrella | s2679 | Pierre SIBANARCO | CC0 | https://bigsoundbank.com/rain-under-an-umbrella-s2679.html | 0s to 30s, 25s loop |
| forest.m4a | Countryside | s0097 | Joseph SARDIN | CC0 | https://bigsoundbank.com/campagne-s0097.html | 6s to 71s, 60s loop |
| birds.m4a | Birds Waking #4 | s1906 | Joseph SARDIN | CC0 | https://bigsoundbank.com/reveil-des-oiseaux-4-s1906.html | 60s to 125s, 60s loop |
| stream.m4a | Forest and Stream #1 | s2713 | Pierre SIBANARCO | CC0 | https://bigsoundbank.com/foret-et-ruisseau-1-s2713.html | 40s to 105s, 60s loop |
| lake.m4a | Small waves and beach #2 | s1448 | Joseph SARDIN | CC0 | https://bigsoundbank.com/small-waves-and-beach-2-s1448.html | 120s to 215s, 90s loop |

Not yet sourced: cottage (a fireplace and room tone), and a real wind recording.
