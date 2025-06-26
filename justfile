# Copy contract ABI to clipboard
copy-abi name:
    jq .abi out/{{name}}.sol/{{name}}.json | pbcopy
