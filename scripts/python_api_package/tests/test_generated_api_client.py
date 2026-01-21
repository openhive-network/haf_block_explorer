from __future__ import annotations

from typing import Final

from tests.api_caller import HafbeApiCaller

from beekeepy._communication.is_url_reachable import async_get_first_reachable_url
from beekeepy._communication.url import HttpUrl

FALLBACK_ENDPOINTS: Final[list[HttpUrl]] = [
    HttpUrl("https://api.syncad.com"),
    HttpUrl("https://api.hive.blog"),
]
SEARCHED_ACCOUNT_IN_TESTS: Final[str] = "gtg"


async def test_generated_api_client():
    # ARRANGE
    endpoint = await async_get_first_reachable_url(FALLBACK_ENDPOINTS)
    api_caller = HafbeApiCaller(endpoint_url=endpoint)

    # ACT
    async with api_caller as api:
        result = await api.api.hafbe_api.accounts(SEARCHED_ACCOUNT_IN_TESTS)

    # ASSERT
    assert result.name == SEARCHED_ACCOUNT_IN_TESTS, "Expected account name to match the searched account."
