import json
import sys

request = json.load(sys.stdin)
if request.get("apiVersion") != 1:
    response = {"apiVersion": 1, "error": {"message": "Unsupported API"}}
elif request["method"] == "commands/execute" and request["name"] == "about":
    response = {"apiVersion": 1, "result": "Text Utilities was loaded from a plugin folder. This message comes from plugin.py, independently of OneCap’s core code."}
elif request["method"] == "tools/call" and request["name"] == "count-words":
    text = request["arguments"]["text"]
    response = {"apiVersion": 1, "result": {"words": len(text.split()), "characters": len(text)}}
else:
    response = {"apiVersion": 1, "error": {"message": "Unknown feature"}}
json.dump(response, sys.stdout)
