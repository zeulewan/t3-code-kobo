# T3 Code Kobo

Lightweight KOReader client for T3 Code. It runs on Kobo through KOReader and talks to a small workstation bridge.

## What It Does

- Lists active T3 agents/threads.
- Opens a minimal chat view with KOReader's keyboard.
- Sends normal T3 user turns through the bridge.
- Streams updates by reading a long-lived bridge response into a local file.

## Install

Copy the plugin folder to KOReader:

```sh
cp -r koreader-t3code.koplugin /path/to/koreader/plugins/
```

Run the bridge on the workstation that runs T3:

```sh
mkdir -p "$HOME/.t3/kobo-bridge"
cp bridge/t3-kobo-bridge.mjs bridge/start.sh "$HOME/.t3/kobo-bridge/"
T3_KOBO_BRIDGE_HOST=0.0.0.0 "$HOME/.t3/kobo-bridge/start.sh"
```

In KOReader, open `T3 Code`, choose `Custom`, and enter:

```text
<thread-or-agent-name> <bridge-host>:18891
```

## Notes

- The bridge reads T3 state via `/api/orchestration/snapshot` and sends turns via `/api/orchestration/dispatch`.
- No secrets are stored in the plugin. The bridge creates a local owner session with `t3 auth session issue`.
- Defaults are generic; set host, port, base dir, and target through environment variables or the plugin pairing screen.

## License

MIT
