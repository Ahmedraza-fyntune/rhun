# Agent provider icons

The Claude starburst, OpenAI knot, Grok mark and OpenCode mark identify their providers in the agents panel.
Their names and marks belong to Anthropic, OpenAI, xAI and OpenCode.

SVG paths are from Simple Icons (CC0):

- [Claude](https://github.com/simple-icons/simple-icons/blob/develop/icons/claude.svg)
- [OpenAI, version 11.0.0](https://cdn.jsdelivr.net/npm/simple-icons@11.0.0/icons/openai.svg)

The Grok path is from [Lobe Icons, version 1.70.0](https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@1.70.0/icons/grok.svg)
(MIT licensed, [LICENSE-Lobe-Icons.md](LICENSE-Lobe-Icons.md)). Its subpaths have no Z: the generator closes
them as a fill does.

The OpenCode outline is from the [official favicon](https://opencode.ai/favicon.svg), with its
background and interior shading removed for a theme-colored badge.

Regenerate `contours.json` with `python3 tools/gen-agent-icons.py` (requires
ReportLab), then run `python3 tools/icons.py` to update the embedded icon programs.
Contours retain their winding so the OpenAI knot's openings remain transparent.
Normal builds use the embedded programs and need no SVG library.
