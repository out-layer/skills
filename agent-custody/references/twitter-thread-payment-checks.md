# Twitter Thread: Payment Checks

**1/**
Payment Checks are live in OutLayer Agent Custody.

Gasless, atomic agent-to-agent payments on @NEARIntents. No RPC polling. No double-spend. No escrow.

An API key and 4 calls — and your agents can pay each other in any of 200+ NEAR Intents assets.

Here's how it works:

**2/**
The problem: AI agents paying each other is hard.

Regular transfers can't be reversed. Escrow contracts are complex and expensive. Polling tx status is fragile. And if the seller never delivers — funds are gone.

Agents need something dead simple.

**3/**
Payment Checks = cashier's checks for AI agents.

Buyer locks funds into a TEE-derived keypair on @NEARIntents. Seller gets a check_key.

First to claim gets the money. Atomic — no RPC checks needed. No double-spend possible. The blockchain handles it.

**4/**
The entire flow is gasless. Zero NEAR needed on the wallet.

Create, claim, reclaim — all signed as NEP-413 intents. The solver relay pays gas.

Agents operate with just an API key. No private key management. No gas estimation.

**5/**
Built on NEAR Intents Gifts, but with agent-grade features:

- Partial claims (claim in parts as milestones complete)
- Partial reclaims (take back unused portion)
- Expiry dates (protect against forgotten checks)
- Batch creation (up to 10 checks at once)

**6/**
Partial claims are the killer feature.

Create 1 check for 10 USDC, 3-milestone project.

Seller claims 3 USDC per milestone. After 2 milestones the buyer cancels — reclaims remaining 4 USDC.

One check. Multiple payments. Both sides protected.

**7/**
Keys are derived in TEE from the custody keystore.

The server never stores raw private keys. If it restarts, every key is re-derived from master key + counter.

Agent Custody guarantees your agent never loses a check key. No key DB to leak.

**8/**
The simplest possible agent logic:

POST /payment-check/create
  -> check_key (send to seller)

POST /payment-check/claim
  -> funds in seller's intents balance

That's the whole integration. One call to pay, one to collect. Status is optional.

**9/**
Expiry protects the buyer.

Set expires_in: 86400 (24h). If the seller doesn't claim in time, the check expires. Buyer calls /reclaim — funds return.

No cron jobs, no auto-reclaim. Buyer stays in control.

**10/**
Interoperable with the full NEAR Intents ecosystem.

Our agents claim via API. External wallets claim on-chain using the check_key as a NEAR Intents Gift key directly.

Both paths work. No vendor lock-in.

**11/**
What agents build with this:

- Pay-per-task (generate image, analyze data, write code)
- Milestone-based projects
- Multi-agent pipelines where each step gets paid
- Bounties and tip jars
- Any agent-to-agent commerce

**12/**
Payment Checks are live now.

USDC, USDT, wNEAR, or any of 200+ tokens across 25+ chains.

Docs: skills.outlayer.ai/agent-custody/SKILL.md

Build agents that pay agents.
