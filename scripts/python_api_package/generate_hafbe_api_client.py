from __future__ import annotations

import sys
from pathlib import Path

from api_client_generator.rest import generate_api_client_from_swagger
from beekeepy.handle.remote import AbstractAsyncApi


if __name__ == "__main__":

    if len(sys.argv) != 3:
        raise ValueError(
            "Usage: python generate_hafbe_api_client.py <base_directory> <build_directory>"
        )


    base_directory = Path(sys.argv[1])
    build_directory = Path(sys.argv[2])

    swagger_hafbe_api_definition = build_directory / "swagger-doc.json"
    hafbe_api_client_output_package = base_directory / "hafbe_api" / "hafbe_api_client"

    generate_api_client_from_swagger(
        swagger_hafbe_api_definition,
        hafbe_api_client_output_package,
        AbstractAsyncApi,
    )
