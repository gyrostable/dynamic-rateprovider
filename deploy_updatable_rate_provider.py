import argparse

import dotenv

import subprocess
import os
from decimal import Decimal

from constants import CONTRACT_ADDRESSES, DEFAULT_ADMINS


def main():
    dotenv.load_dotenv()

    parser = argparse.ArgumentParser(description="Deploy an updatable rateprovider")
    parser.add_argument(
        "--chain",
        choices=CONTRACT_ADDRESSES.keys(),
        required=True,
        help="Chain to use.",
    )
    parser.add_argument(
        "bal_version", choices=["v2", "v3"], help="Balancer version to use"
    )
    parser.add_argument("feed", help="Connected price feed")
    parser.add_argument(
        "--admin",
        required=True,
        type=str,
        help="Admin. Pass 'deployer' to use the deployer itself or 'default' to use the default admin for that chain (see constants.py). Pass 'none' to disable admin.",
    )
    parser.add_argument(
        "--updater",
        required=True,
        type=str,
        help="Updater. Pass 'deployer' to use the deployer itself or 'none' to not set up anything at deployment. If 'none', you need to manually configure an updater later.",
    )
    parser.add_argument(
        "--invert",
        action="store_true",
        help="If passed, use 1/(feed value) instead of the feed value itself",
    )
    parser.add_argument(
        "--initial-value",
        type=Decimal,
        help="If passed, use the given value (an unscaled decimal) as the initial value of the updatable rateprovider; otherwise, use the current feed value (default)",
    )
    parser.add_argument(
        "--broadcast",
        action="store_true",
        help="Broadcast. Otherwise, we just simulate.",
    )

    args = parser.parse_args()

    deployer_address = subprocess.run(
        ["cast", "wallet", "address", os.environ["PRIVATE_KEY"]],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

    # Set admin
    if args.admin == "deployer":
        admin = deployer_address
    elif args.admin == "default":
        admin = DEFAULT_ADMINS[args.chain]
    elif args.admin == "none":
        admin = "0x0000000000000000000000000000000000000000"
    else:
        admin = args.admin

    if args.updater == "deployer":
        updater = deployer_address
    elif args.updater == "none":
        updater = "0x0000000000000000000000000000000000000000"
    else:
        updater = args.updater

    contract_addresses = CONTRACT_ADDRESSES[args.chain]

    rpc_url = os.environ[f"{args.chain.upper()}_RPC_URL"]

    if args.initial_value:
        initial_value = int(args.initial_value * Decimal("1e18"))
    else:
        initial_value = 0

    if args.bal_version == "v2":
        cmd = [
            "forge",
            "script",
            "script/DeployUpdatableRateProviderBalV2.sol",
            # "--chain",
            # args.chain,
            "--rpc-url",
            rpc_url,
            "-s",
            "run(address,bool,uint256,address,address,address,address)",
            args.feed,
            ("true" if args.invert else "false"),
            initial_value,
            admin,
            updater,
            contract_addresses["gyro_config_manager"],
            contract_addresses["governance_role_manager"],
        ]
        if args.broadcast:
            cmd.append("--broadcast")
        print(" ".join(cmd))
        subprocess.run(cmd, text=True, capture_output=False, check=True)
    else:
        raise NotImplementedError("Not implemented: Bal V3 deployment.")


if __name__ == "__main__":
    main()
