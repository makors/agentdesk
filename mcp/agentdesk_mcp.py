#!/usr/bin/env python3
"""Minimal stdio MCP server for agentdesk. Wraps the agentdesk CLI.
Tools: desk_open(app, file?), desk_close(desk_id), desk_status().
It does NOT do computer use; it prepares an isolated hidden workspace and returns the
process id + window id for the host's own background computer use to drive."""
import sys, json, subprocess, pathlib
HERE = pathlib.Path(__file__).resolve().parent
def _find_agentdesk():
    import os
    for c in (HERE/'agentdesk', HERE.parent/'bin'/'agentdesk', HERE.parent/'cli'/'agentdesk',
              pathlib.Path.home()/'.agentdesk'/'bin'/'agentdesk'):
        if c.exists():return c
    return 'agentdesk'  # rely on PATH
AGENTDESK = _find_agentdesk()
def cli(*args, timeout=90):
    try:
        r = subprocess.run(['python3', str(AGENTDESK), *args], capture_output=True, text=True, timeout=timeout)
        return (r.stdout.strip() or r.stderr.strip() or f'(exit {r.returncode})')
    except Exception as e:
        return f'error: {e}'
TOOLS = [
  {"name":"desk_open",
   "description":"Open an ISOLATED, HIDDEN workspace: a SEPARATE process instance of <app> parked on a hidden display at the corner of the screen, out of the user's way. Returns the app's pid and window_id. Drive that pid/window_id with your normal background computer use; do NOT bring it to the front. Any dialog it opens is moved off the user's screen automatically. Optionally pass an absolute <file> path to open it directly with no file picker.",
   "inputSchema":{"type":"object","properties":{"app":{"type":"string","description":"Application name, e.g. 'TextEdit', 'Preview', 'Adobe Illustrator 2026'"},"file":{"type":"string","description":"Optional absolute path to a file to open directly"}},"required":["app"]}},
  {"name":"desk_close",
   "description":"Close a desk opened with desk_open: quit that app instance and stop watching it.",
   "inputSchema":{"type":"object","properties":{"desk_id":{"type":["string","integer"],"description":"The desk id (the pid) returned by desk_open"}},"required":["desk_id"]}},
  {"name":"desk_status",
   "description":"Report agentdesk status: the hidden display, the desks being watched, and how many dialogs have been moved off-screen.",
   "inputSchema":{"type":"object","properties":{}}},
]
def call_tool(name, args):
    if name == 'desk_open':
        cli('up')
        c = ['launch', str(args['app'])]
        if args.get('file'): c += ['--file', str(args['file'])]
        return cli(*c)
    if name == 'desk_close':
        return cli('close', str(args['desk_id']))
    if name == 'desk_status':
        return cli('status')
    return json.dumps({'error': f'unknown tool {name}'})
def reply(mid, result=None, error=None):
    msg = {"jsonrpc":"2.0","id":mid}
    if error is not None: msg["error"] = error
    else: msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n"); sys.stdout.flush()
def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: req = json.loads(line)
        except Exception: continue
        method = req.get('method'); mid = req.get('id'); params = req.get('params') or {}
        if method == 'initialize':
            reply(mid, {"protocolVersion": params.get('protocolVersion','2024-11-05'),
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name":"agentdesk","version":"0.1.0"}})
        elif method == 'notifications/initialized' or mid is None:
            continue  # notification, no response
        elif method == 'tools/list':
            reply(mid, {"tools": TOOLS})
        elif method == 'tools/call':
            try:
                text = call_tool(params.get('name'), params.get('arguments') or {})
                reply(mid, {"content":[{"type":"text","text": text}], "isError": False})
            except Exception as e:
                reply(mid, {"content":[{"type":"text","text": f"error: {e}"}], "isError": True})
        elif method == 'ping':
            reply(mid, {})
        else:
            reply(mid, error={"code":-32601,"message":f"method not found: {method}"})
if __name__ == '__main__':
    main()
