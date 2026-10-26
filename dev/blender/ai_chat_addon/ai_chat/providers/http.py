"""Small JSON-over-HTTPS helpers shared by providers (standard library only)."""

import json
import socket
import urllib.error
import urllib.request

from .base import ProviderError


def request_json(url, *, service, headers=None, body=None, timeout=60.0, error_message=None):
    """Send a GET (body None) or POST and return the decoded JSON response.

    `error_message(status, payload)` turns an HTTP error into UI text; payload is
    the decoded error body or None.
    """
    headers = dict(headers or {})
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["content-type"] = "application/json"
    request = urllib.request.Request(
        url, data=data, headers=headers, method="POST" if data is not None else "GET"
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read().decode("utf-8"))
        except Exception:
            payload = None
        raise ProviderError(error_message(e.code, payload)) from None
    except urllib.error.URLError as e:
        if isinstance(e.reason, (socket.timeout, TimeoutError)):
            raise ProviderError(f"Request timed out after {timeout:.0f}s") from None
        raise ProviderError(f"Could not reach the {service} API: {e.reason}") from None
    except (socket.timeout, TimeoutError):
        raise ProviderError(f"Request timed out after {timeout:.0f}s") from None
    except json.JSONDecodeError:
        raise ProviderError(f"The {service} API returned a response that is not JSON") from None
