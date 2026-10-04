# Agent provider icons

The Claude starburst and OpenAI knot identify their providers in the agents panel.
Their names and marks belong to Anthropic and OpenAI.

SVG paths are from Simple Icons (CC0):

- [Claude](https://github.com/simple-icons/simple-icons/blob/develop/icons/claude.svg)
- [OpenAI, version 11.0.0](https://cdn.jsdelivr.net/npm/simple-icons@11.0.0/icons/openai.svg)

Regenerate `contours.json` with `python3 tools/gen-agent-icons.py` (requires
ReportLab), then run `python3 tools/icons.py` to update the embedded icon programs.
Contours retain their winding so the OpenAI knot's openings remain transparent.
Normal builds use the embedded programs and need no SVG library.
