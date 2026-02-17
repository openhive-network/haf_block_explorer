from __future__ import annotations

from beekeepy.handle.remote import AsyncSendable

from hiveio_hafbe_api.hafbe_api_client.hafbe_api_client import HafbeApi


class HafbeApiCollection:
    def __init__(self, owner: AsyncSendable) -> None:
        self.hafbe_api = HafbeApi(owner=owner)
