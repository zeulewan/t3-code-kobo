# T3 Code Kobo

Lightweight KOReader client for T3 Code. It runs on Kobo through KOReader and talks to a small workstation bridge.

## What It Does

- Lists active T3 agents/threads.
- Opens a minimal chat view with KOReader's keyboard.
- Sends normal T3 user turns through the bridge.
- Streams updates through a workstation bridge that subscribes to T3 over WebSocket, then exposes a Kobo-friendly long-poll `/events` endpoint.
- Renders a small Markdown subset in chat: bold and headings use KOReader's lightweight text formatter; italics/code/links are simplified to readable text.

## Install

Copy the plugin folder to KOReader:

```sh
cp -r koreader-t3code.koplugin /path/to/koreader/plugins/
```

Run the bridge on the workstation that runs T3:

```sh
mkdir -p "$HOME/.t3/kobo-bridge"
cp bridge/t3-kobo-bridge.mjs bridge/start.sh "$HOME/.t3/kobo-bridge/"
T3_KOBO_BRIDGE_HOST=0.0.0.0 T3_KOBO_T3CODE_REPO=/path/to/t3code "$HOME/.t3/kobo-bridge/start.sh"
```

In KOReader, open `T3 Code`, choose `Custom`, and enter:

```text
<thread-or-agent-name> <bridge-host>:18891
```

## Notes

- Run the bridge with Bun. It imports T3's client runtime and subscribes to thread events over the real T3 WebSocket.
- The bridge reads initial state via `/api/orchestration/snapshot`, sends turns via `/api/orchestration/dispatch`, and exposes incremental `/events` frames for the Kobo.
- No secrets are stored in the plugin. The bridge creates a local owner session with `t3 auth session issue`.
- Defaults are generic; set host, port, base dir, and target through environment variables or the plugin pairing screen.
- If using Tailscale, expose the bridge as raw TCP/HTTP. Do not put Tailscale Serve HTTPS on the same port because Kobo BusyBox `wget` expects plain HTTP.
- True italic glyphs require KOReader's heavier HTML/MuPDF widget; the current chat viewport intentionally stays on the cheaper text widget for streaming.

## License

MIT
