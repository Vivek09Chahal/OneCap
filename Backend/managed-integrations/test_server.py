import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from server import Bridge, Failure


class Provider:
    def __init__(self):
        self.calls = []
        self.accounts = {}
        self.next_status = "ACTIVE"

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        if path == "connected_accounts/link":
            account = "ca_" + str(len(self.accounts))
            toolkit = body["auth_config_id"].removeprefix("ac_")
            self.accounts[account] = {"user_id": body["user_id"], "toolkit": {"slug": toolkit},
                                      "auth_config": {"id": body["auth_config_id"]}, "status": self.next_status}
            return {"connected_account_id": account, "redirect_url": "https://connect.composio.dev/link/secret"}
        if path.startswith("connected_accounts/"):
            if method == "DELETE":
                self.accounts.pop(path.split("/")[-1], None)
                return {}
            return self.accounts[path.split("/")[-1]]
        if path.startswith("tools?"):
            return {"items": [{"slug": toolkit.upper() + "_SEARCH", "toolkit": {"slug": toolkit},
                               "description": "Search", "version": "20261101_00",
                               "input_parameters": {"type": "object", "properties": {}}}
                              for toolkit in ["gmail", "googlecalendar", "figma", "notion", "github"]]}
        if path.startswith("tools/execute/"):
            return {"successful": True, "data": {"result": "found"}}
        raise AssertionError(path)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.provider = Provider()
        self.config = {slug: {"toolkit": slug, "authConfigID": "ac_" + slug}
                       for slug in ["gmail", "googlecalendar", "figma", "notion", "github"]}
        self.database = str(Path(self.tmp.name) / "test.sqlite3")
        self.users = {hashlib.sha256(token.encode()).hexdigest(): owner
                      for token, owner in [("alice-token", "alice"), ("bob-token", "bob")]}
        self.bridge = Bridge(self.database, self.users, self.config, self.provider)

    def handle(self, method, path, body=None, token="alice-token"):
        return self.bridge.handle(method, path, "Bearer " + token, body)

    def connect(self, plugin="gmail"):
        return self.handle("POST", "/v1/connections", {"pluginID": plugin})[1]["id"]

    def test_all_services_use_browser_link_and_scoped_tools(self):
        for slug in self.config:
            with self.subTest(slug=slug):
                identifier = self.connect(slug)
                path = "/v1/connections/" + identifier
                self.assertEqual(self.handle("GET", path)[1]["status"], "ACTIVE")
                tools = self.handle("POST", path + "/mcp", {"id": 1, "method": "tools/list"})[1]["result"]["tools"]
                self.assertEqual([t["name"] for t in tools], [slug.upper() + "_SEARCH"])
                self.handle("POST", path + "/mcp", {"id": 2, "method": "tools/call", "params": {
                    "name": tools[0]["name"], "arguments": {"query": "hi"},
                    "connected_account_id": "someone-else", "user_id": "bob"}})
                execution = self.provider.calls[-1][2]
                self.assertEqual(execution["user_id"], "alice")
                self.assertEqual(execution["connected_account_id"], self.bridge.owned("alice", identifier)["account"])
                self.assertNotIn("secret", json.dumps(self.handle("GET", path)))

    def test_other_users_cannot_read_execute_or_delete(self):
        path = "/v1/connections/" + self.connect()
        for method, suffix in [("GET", ""), ("DELETE", ""), ("POST", "/mcp")]:
            with self.assertRaises(Failure) as error:
                self.handle(method, path + suffix, {"method": "tools/list"}, token="bob-token")
            self.assertEqual(error.exception.status, 404)

    def test_unknown_tool_or_cross_toolkit_cannot_execute(self):
        path = "/v1/connections/" + self.connect() + "/mcp"
        for name in ["FIGMA_SEARCH", "UNKNOWN", "../proxy"]:
            with self.assertRaises(Failure):
                self.handle("POST", path, {"id": 1, "method": "tools/call", "params": {"name": name}})
        self.assertFalse(any(path.startswith("tools/execute/") for _, path, _ in self.provider.calls))

    def test_expired_or_mismatched_accounts_cannot_execute(self):
        identifier = self.connect()
        account = self.provider.accounts[self.bridge.owned("alice", identifier)["account"]]
        for field, value in [("status", "EXPIRED"), ("user_id", "bob"), ("toolkit", {"slug": "figma"})]:
            original = account[field]
            account[field] = value
            with self.assertRaises(Failure):
                self.handle("POST", "/v1/connections/" + identifier + "/mcp", {"method": "tools/list"})
            account[field] = original

    def test_persistence_close_and_disconnect_are_distinct(self):
        path = "/v1/connections/" + self.connect("figma")
        self.bridge = Bridge(self.database, self.users, self.config, self.provider)
        self.handle("DELETE", path + "/mcp")
        self.assertEqual(self.handle("GET", path)[1]["status"], "ACTIVE")
        self.handle("DELETE", path)
        self.assertEqual(self.provider.accounts, {})
        with self.assertRaises(Failure):
            self.handle("GET", path)

    def test_cancel_pending_connection(self):
        self.provider.next_status = "INITIATED"
        path = "/v1/connections/" + self.connect()
        self.assertEqual(self.handle("GET", path)[1]["status"], "INITIATED")
        self.handle("DELETE", path)
        self.assertEqual(self.provider.accounts, {})

    def test_requires_auth_and_configured_connector(self):
        with self.assertRaises(Failure) as error:
            self.handle("GET", "/v1/catalog", token="wrong")
        self.assertEqual(error.exception.status, 401)
        with self.assertRaises(Failure) as error:
            self.connect("unsupported")
        self.assertEqual(error.exception.status, 409)
        self.assertFalse(self.provider.calls)

    def test_legacy_input_property_map_converts_to_json_schema(self):
        result = Bridge.schema({"input_parameters": {"query": {"type": "string", "required": True}}})
        self.assertEqual(result, {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]})


if __name__ == "__main__":
    unittest.main()
