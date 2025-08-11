from __future__ import annotations

from typing import Final

from tests.api_caller import HafbeApiCaller

from beekeepy._communication.url import HttpUrl

DEFAULT_ENDPOINT_FOR_TESTS: Final[HttpUrl] = HttpUrl("https://api.syncad.com")
SEARCHED_ACCOUNT_IN_TESTS: Final[str] = "gtg"

async def test_generated_api_client():
    # ARRANGE
    api_caller = HafbeApiCaller(endpoint_url=DEFAULT_ENDPOINT_FOR_TESTS)

    # ACT
    async with api_caller as api:
        result = await api.api.hafbe_api.accounts(SEARCHED_ACCOUNT_IN_TESTS)

    # ASSERT
    assert result.name == SEARCHED_ACCOUNT_IN_TESTS, "Expected account name to match the searched account."
