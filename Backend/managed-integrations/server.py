"""OneCap's managed account bridge. Python 3.11+, no third-party dependencies."""
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class Failure(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Composio:
    def __init__(self, key):
        self.key = key

    def request(self, method, path, body=None):
        request = Request("https://backend.composio.dev/api/v3.1/" + path,
                          data=None if body is None else json.dumps(body).encode(), method=method,
                          headers={"x-api-key": self.key, "Content-Type": "application/json"})
        try:
            with build_opener(NoRedirect).open(request, timeout=60) as response:
                data = response.read(4 * 1024 * 1024 + 1)
                if len(data) > 4 * 1024 * 1024:
                    raise Failure(502, "Connector response is too large.")
                return json.loads(data) if data else {}
        except HTTPError as error:
            if method == "DELETE" and error.code == 404:
                return {}
            raise Failure(502, "Account service request failed. Please retry or reconnect.") from None
        except (URLError, ValueError, TimeoutError):
            raise Failure(502, "Account service is unavailable. Please retry.") from None


class Bridge:
    def __init__(self, database, users, connectors, provider):
        self.database, self.users, self.connectors, self.provider = database, users, connectors, provider
        with self.db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS connections "
                       "(id TEXT PRIMARY KEY, owner TEXT, plugin TEXT, account TEXT, created REAL)")

    def db(self):
        db = sqlite3.connect(self.database, timeout=30)
        db.row_factory = sqlite3.Row
        return db

    def authenticate(self, authorization):
        if not authorization.startswith("Bearer "):
            raise Failure(401, "Sign in to OneCap connections again.")
        digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
        for expected, owner in self.users.items():
            if hmac.compare_digest(digest, expected):
                return owner
        raise Failure(401, "Sign in to OneCap connections again.")

    def owned(self, owner, identifier):
        with self.db() as db:
            row = db.execute("SELECT * FROM connections WHERE id=? AND owner=?", (identifier, owner)).fetchone()
        if not row:
            raise Failure(404, "Connection not found.")
        return dict(row)

    def account(self, row):
        account = self.provider.request("GET", "connected_accounts/" + quote(row["account"], safe=""))
        config = self.connectors[row["plugin"]]
        if (account.get("user_id") != row["owner"] or
                account.get("toolkit", {}).get("slug") != config["toolkit"] or
                account.get("auth_config", {}).get("id") != config["authConfigID"]):
            raise Failure(403, "Account does not match this connection.")
        return account

    def tools(self, plugin):
        config = self.connectors[plugin]
        query = {"toolkit_slug": config["toolkit"], "important": "true", "include_deprecated": "false", "limit": 100}
        page = self.provider.request("GET", "tools?" + urlencode(query))
        # Restrict execution to the exact toolkit and the tools exposed to the client.
        return {tool["slug"]: tool for tool in page["items"]
                if tool.get("toolkit", {}).get("slug") == config["toolkit"] and not tool.get("is_deprecated")}

    @staticmethod
    def schema(tool):
        schema = tool.get("input_parameters", {})
        if schema.get("type") == "object":
            return schema
        # Some API versions return a property map instead of a JSON Schema root.
        return {"type": "object", "properties": {
            key: {k: v for k, v in value.items() if k != "required"} for key, value in schema.items()
        }, "required": [key for key, value in schema.items() if value.get("required") is True]}

    def mcp(self, row, payload):
        method, params = payload.get("method"), payload.get("params", {})
        if method == "notifications/initialized":
            return 202, None
        if method == "initialize":
            result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                      "serverInfo": {"name": "OneCap managed connections", "version": "1.0"}}
        elif method in ("tools/list", "tools/call"):
            account = self.account(row)
            if account.get("status") != "ACTIVE" or account.get("is_disabled"):
                raise Failure(401, "This account needs to be reconnected in Plugins.")
            tools = self.tools(row["plugin"])
            if method == "tools/list":
                result = {"tools": [{"name": slug, "description": tool.get("description", ""),
                                     "inputSchema": self.schema(tool)} for slug, tool in tools.items()]}
            else:
                tool = tools.get(params.get("name"))
                if not tool or not isinstance(params.get("arguments", {}), dict):
                    raise Failure(400, "Tool is not available for this connected app.")
                output = self.provider.request("POST", "tools/execute/" + quote(tool["slug"], safe=""), {
                    "connected_account_id": row["account"], "user_id": row["owner"],
                    "version": tool.get("version", "latest"), "arguments": params.get("arguments", {})})
                if not output.get("successful"):
                    result = {"isError": True, "content": [{"type": "text", "text": "The app action failed. Check its inputs or reconnect the account."}]}
                else:
                    result = {"content": [{"type": "text", "text": json.dumps(output.get("data", {}))}]}
        else:
            return 200, {"jsonrpc": "2.0", "id": payload.get("id"), "error": {"code": -32601, "message": "Method not found"}}
        return 200, {"jsonrpc": "2.0", "id": payload.get("id"), "result": result}

    def handle(self, method, path, authorization, payload=None):
        owner = self.authenticate(authorization)
        if path == "/v1/catalog" and method == "GET":
            return 200, {"plugins": list(self.connectors)}
        if path == "/v1/connections" and method == "POST":
            plugin = payload.get("pluginID")
            if plugin not in self.connectors:
                raise Failure(409, "Account connection is not configured for this app yet.")
            link = self.provider.request("POST", "connected_accounts/link", {
                "user_id": owner, "auth_config_id": self.connectors[plugin]["authConfigID"]})
            url = urlsplit(link["redirect_url"])
            if url.scheme != "https" or url.hostname != "connect.composio.dev" or url.username or url.password:
                raise Failure(502, "Account service returned an invalid sign-in link.")
            identifier = str(uuid.uuid4())
            with self.db() as db:
                db.execute("INSERT INTO connections VALUES (?, ?, ?, ?, ?)",
                           (identifier, owner, plugin, link["connected_account_id"], time.time()))
            return 201, {"id": identifier, "redirectURL": link["redirect_url"]}
        match = re.fullmatch(r"/v1/connections/([0-9a-f-]{36})(/mcp)?", path)
        if not match:
            raise Failure(404, "Not found.")
        row = self.owned(owner, match[1])
        if row["plugin"] not in self.connectors:
            raise Failure(409, "This connector is no longer configured.")
        if match[2]:
            if method == "DELETE":  # MCP session close does not disconnect the account.
                return 204, None
            if method == "POST" and isinstance(payload, dict):
                return self.mcp(row, payload)
        elif method == "GET":
            account = self.account(row)
            status = "DISABLED" if account.get("is_disabled") else account.get("status", "INITIALIZING")
            return 200, {"status": status}
        elif method == "DELETE":
            self.provider.request("DELETE", "connected_accounts/" + quote(row["account"], safe=""))
            with self.db() as db:
                db.execute("DELETE FROM connections WHERE id=? AND owner=?", (row["id"], owner))
            return 204, None
        raise Failure(405, "Method not allowed.")


def handler(bridge):
    class Handler(BaseHTTPRequestHandler):
        def serve(self):
            try:
                if self.headers.get("Transfer-Encoding"):
                    raise Failure(400, "Unsupported request encoding.")
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 <= length <= 1024 * 1024:
                    raise Failure(413, "Request is too large.")
                payload = json.loads(self.rfile.read(length)) if length else None
                if payload is not None and not isinstance(payload, dict):
                    raise Failure(400, "Expected a JSON object.")
                status, body = bridge.handle(self.command, self.path, self.headers.get("Authorization", ""), payload)
            except Failure as error:
                status, body = error.status, {"error": error.message}
            except (ValueError, TypeError, KeyError):
                status, body = 400, {"error": "Invalid request or connector response."}
            except Exception:
                status, body = 500, {"error": "Connection service failed. Please retry."}
            data = json.dumps(body).encode() if body is not None else b""
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_DELETE = serve

        def log_message(self, *args):
            pass  # Never log link tokens, tool arguments, or account data.
    return Handler


if __name__ == "__main__":
    os.umask(0o077)
    bridge = Bridge(os.environ.get("ONECAP_DATABASE", "connections.sqlite3"),
                    json.loads(os.environ["ONECAP_USER_TOKEN_HASHES"]),
                    json.loads(os.environ["ONECAP_CONNECTORS"]), Composio(os.environ["COMPOSIO_API_KEY"]))
    ThreadingHTTPServer((os.environ.get("ONECAP_BIND", "127.0.0.1"),
                         int(os.environ.get("PORT", "8787"))), handler(bridge)).serve_forever()
