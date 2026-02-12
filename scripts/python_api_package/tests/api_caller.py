from __future__ import annotations

from beekeepy.interfaces import HttpUrl
from beekeepy.handle.remote import AbstractAsyncHandle, RemoteHandleSettings, AsyncBatchHandle
from beekeepy.handle.runnable import RunnableHandleSettings

from tests.api_collection import HafbeApiCollection


class HafbeApiCaller(AbstractAsyncHandle[RemoteHandleSettings, HafbeApiCollection]):
    def __init__(self, endpoint_url: HttpUrl) -> None:
        settings = RunnableHandleSettings()
        settings.http_endpoint = endpoint_url
        super().__init__(settings=settings)


    @property
    def api(self) -> HafbeApiCollection:
        return super().api

    async def batch(self, *, delay_error_on_data_access: bool = False) -> AsyncBatchHandle[ApiCollectionT]:
        return AsyncBatchHandle(
            url=self.http_endpoint,
            overseer=self._overseer,
            api=lambda owner: HafbeApiCollection(owner=owner),
            delay_error_on_data_access=delay_error_on_data_access,
        )

    def _construct_api(self) -> HafbeApiCollection:
        return HafbeApiCollection(owner=self)

    def _target_service(self) -> str:
        return "hived"
