import argparse

POOL_TYPE = {
    "eclp": 0,
    "2clp": 1,
}

parser = argparse.ArgumentParser(
    description="Mini script to get a PoolType value for .setPool()"
)
parser.add_argument("pool_type", choices=POOL_TYPE.keys())
args = parser.parse_args()
print(POOL_TYPE[args.pool_type])
