---
name: outlayer
description: Entry point to the OutLayer skills — which skill to load for a task. OutLayer gives an AI agent a TEE-held multi-chain custody wallet, connectors to outside services (GitHub, Gmail, Mercury, Hyperliquid, Polymarket) under the owner's policy, and verifiable off-chain compute callable over HTTPS or from a NEAR contract. Use when an agent needs to hold or move money, act on an outside service as its owner, find out what it could do for its owner, or build, deploy and run OutLayer applications.
---

# OutLayer skills

OutLayer, on NEAR: an agent registers a custody wallet whose keys live in an
Intel TDX enclave, spends from it under an owner-set policy, reaches outside
services through priced **connectors** that run in the same enclave, and can
run its own WASI code there — from HTTPS or from a NEAR contract.

## Read this page, then load ONE skill

Each skill below is self-contained: its `SKILL.md` covers the common case and
routes to its own `references/` for the rest. **Load the skill for the task in
front of you; do not load them all.**

Every skill is at `https://skills.outlayer.ai/<skill>/SKILL.md`; the files it
points to are relative to that URL.

| The task in front of you | Load |
|---|---|
| Hold, move, swap or sign for money: register a wallet, balances, transfers, cross-chain, confidential, limit orders, payment checks, account binding, payment keys | [`agent-custody`](https://skills.outlayer.ai/agent-custody/SKILL.md) |
| Call any connector: auth, the `operation` field, secrets, fees, the free trial, refusal codes — and what each connector does | [`outlayer-connectors`](https://skills.outlayer.ai/outlayer-connectors/SKILL.md) |
| Find out what you could do for your owner with the connectors, and how to offer it without acting unasked | [`outlayer-connectors/references/offering.md`](https://skills.outlayer.ai/outlayer-connectors/references/offering.md) |
| Act on GitHub as the owner: issues, comments, pull requests, commits, gists | [`github-connector`](https://skills.outlayer.ai/github-connector/SKILL.md) |
| Send email from the owner's Gmail address | [`gmail-connector`](https://skills.outlayer.ai/gmail-connector/SKILL.md) |
| Move USD out of, or invoice into, the owner's Mercury bank account | [`mercury-connector`](https://skills.outlayer.ai/mercury-connector/SKILL.md) |
| Trade Hyperliquid perpetuals from the custody wallet | [`hyperliquid-connector`](https://skills.outlayer.ai/hyperliquid-connector/SKILL.md) |
| Take or close a position on a Polymarket prediction market | [`polymarket-connector`](https://skills.outlayer.ai/polymarket-connector/SKILL.md) |
| Build an OutLayer application: a WASI module in Rust, a NEAR proxy contract, a frontend with wallet-selector, payment keys or NEP-413 auth | [`building-outlayer-apps`](https://skills.outlayer.ai/building-outlayer-apps/SKILL.md) |
| Deploy, run and operate an agent from the command line: scaffolding, deploys, secrets, payment keys, FastFS uploads, versions, earnings | [`outlayer-cli`](https://skills.outlayer.ai/outlayer-cli/SKILL.md) |

Two skills are read together more often than not: a connector's own skill
tells you its operations and policy; `outlayer-connectors` tells you how the
call is made and paid for. Start with the connector's skill; open
`outlayer-connectors` when a call is refused or a key has to be chosen.

## Facts every skill relies on

| | mainnet | testnet |
|---|---|---|
| API base | `https://api.outlayer.ai` | `https://testnet-api.outlayer.ai` |
| Dashboard | `https://app.outlayer.ai` | same, switch the network in the UI |
| Contract | `outlayer.near` | `outlayer.testnet` |
| Curated connectors | `connectors.outlayer.near` | `connectors.outlayer.testnet` |

There is no network parameter anywhere — the host is the choice, and a key
minted on one network means nothing on the other. NEAR Intents (swaps,
cross-chain, intents balances) exist on mainnet only.
