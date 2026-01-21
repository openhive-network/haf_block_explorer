from __future__ import annotations

from typing import Final

import aiohttp

from tests.api_caller import HafbeApiCaller

from beekeepy._communication import HttpUrl

FALLBACK_ENDPOINTS: Final[list[HttpUrl]] = [
    HttpUrl("https://api.syncad.com"),
    HttpUrl("https://api.hive.blog"),
]
SEARCHED_ACCOUNT_IN_TESTS: Final[str] = "gtg"


async def _get_healthy_endpoint(endpoints: list[HttpUrl], service_path: str) -> HttpUrl:
    """Return the first endpoint where the service responds with 2xx status."""
    async with aiohttp.ClientSession() as session:
        for endpoint in endpoints:
            try:
                url = f"{endpoint}{service_path}"
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                    if response.status < 400:
                        return endpoint
            except (aiohttp.ClientError, TimeoutError):
                continue
    raise ValueError(f"No healthy endpoint found for service path: {service_path}")


async def test_generated_api_client():
    # ARRANGE
    endpoint = await _get_healthy_endpoint(FALLBACK_ENDPOINTS, f"/hafbe-api/accounts/{SEARCHED_ACCOUNT_IN_TESTS}")
    api_caller = HafbeApiCaller(endpoint_url=endpoint)

    # ACT
    async with api_caller as api:
        result = await api.api.hafbe_api.accounts(SEARCHED_ACCOUNT_IN_TESTS)

    # ASSERT
    assert result.name == SEARCHED_ACCOUNT_IN_TESTS, "Expected account name to match the searched account."
