"""Registry of chat providers.

To add a provider: subclass providers.base.Provider in a new module, add an
instance to _PROVIDERS, and add `<id>_api_key`, `<id>_model` and
`<id>_custom_model` properties to the preferences.
"""

from .anthropic import AnthropicProvider
from .base import ChatReply, ChatRequest, Provider, ProviderError
from .venice import VeniceProvider

# The first provider is the default.
_PROVIDERS = {p.id: p for p in (VeniceProvider(), AnthropicProvider())}

# Enum items must stay referenced for the lifetime of the add-on.
PROVIDER_ITEMS = [(p.id, p.label, p.description) for p in _PROVIDERS.values()]


def get(provider_id):
    return _PROVIDERS.get(provider_id) or next(iter(_PROVIDERS.values()))


def all_providers():
    return list(_PROVIDERS.values())
