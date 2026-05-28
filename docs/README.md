# docs/

Asset directory for repo documentation.

## Demo recording

The root README references `docs/demo.gif` and `docs/statusline.png`. Drop your captures here.

### Recommended: terminalizer (gif)

```bash
npm install -g terminalizer
terminalizer record demo --command "claude"   # then walk the workflow
terminalizer render demo -o docs/demo.gif
```

Or use [asciinema](https://asciinema.org) + [agg](https://github.com/asciinema/agg) for smaller files:

```bash
asciinema rec demo.cast
agg demo.cast docs/demo.gif --speed 2
```

### Statusline screenshot

Crop just the statusline strip — keep it ~800px wide max so it renders sensibly in the README. PNG preferred for crisp text.

### Asset constraints

- Total `docs/*.gif` under 5 MB combined (GitHub renders larger but mobile users suffer)
- No private data (Jira keys, real tokens, project names) — use the example `ENG-1234 feat-add-dashboard-ssr` slug from the README
- Light terminal background reads better on GitHub's white doc pane
