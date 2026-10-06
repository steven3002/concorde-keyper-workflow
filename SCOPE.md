# Scope

## Overview

This repository provides a credential-isolated reference deployment for a Shutter Keyper monitoring agent using the Concorde framework. It demonstrates how to run an agent workflow that queries permitted public metrics and communicates over Telegram while isolating provider credentials from the agent runtime and strictly constraining container egress.

## Upstream Licencing and Code Acquisition

Neither [`shutter-network/concorde`](https://github.com/shutter-network/concorde) nor [`shutter-network/keyper-concorde-agent`](https://github.com/shutter-network/keyper-concorde-agent) publishes an open-source licence file in their repositories. To respect copyright and distribution constraints, this repository does not redistribute or commit any source code from either upstream project. All required upstream components are fetched directly from their respective source repositories at pinned commit revisions during container image build stages.

## Component Breakdown

### 1. Reused As-Is

- **Concorde Framework Core**: Built directly from upstream commit [`03dda6a`](https://github.com/shutter-network/concorde/commit/03dda6a0b1a79077737342709f346bf463a94e20) into a package tarball. Reuses the gateway server, PostgreSQL persistence and pool management, signal processing worker, user management, and the messenger queue.
- **Telegram Channel**: Extracted from upstream repository [`shutter-network/keyper-concorde-agent`](https://github.com/shutter-network/keyper-concorde-agent) at commit [`f5a5c17`](https://github.com/shutter-network/keyper-concorde-agent/commit/f5a5c17e1f39570f84d953bb46dba0f35f15b3dc) (`telegram-channel/` tree only). Reuses the long-polling loop, chat-to-user mapping, sender metadata extraction, outbound message queue drain logic, and the associated 21 unit/integration tests.
- **Agent Hardening Profile**: Adopts the Linux container hardening constraints defined in Concorde's isolation reference example (`cap_drop: [ALL]`, `no-new-privileges: true`, process limits, and memory limits).

### 2. Already Existing Upstream

- **Keyper Prototype Implementation**: Prior prototype in [`shutter-network/keyper-concorde-agent`](https://github.com/shutter-network/keyper-concorde-agent) based on legacy Concorde commit `e3f746e`, requiring Docker daemon socket mounts and spawning ephemeral container instances per run.
- **Upstream Problem Statement**: Issue [#7: "Restrict agent from exposing environment secrets"](https://github.com/shutter-network/keyper-concorde-agent/issues/7), identifying the need to remove model provider keys from the agent execution environment and restrict outbound network access.
- **Upstream Credential Proxy Proposal**: Pull Request [#19: "feat: litellm-proxy-implementation"](https://github.com/shutter-network/keyper-concorde-agent/pull/19), an unmerged prototype introducing LiteLLM for routing without restricting destination egress, retaining Docker socket mounts, and leaving network routes open.
- **Upstream Framework Isolation Example**: Concorde Pull Request [#16: "feat: add an example that keeps the credential away from the agent…"](https://github.com/shutter-network/concorde/pull/16) (merged into `main` at `03dda6a`), establishing the RPC-based runtime pattern where the agent runs as a dedicated daemon behind a stream listener.

### 3. Implemented in This Repository

- **RPC Runtime Integration for Telegram**: Adapts the upstream Telegram channel to function over Concorde's modern RPC runtime, eliminating Docker daemon socket mounts.
- **Locked Model Relay**: An egress relay implemented using a standard web proxy container with a rigid configuration template: accepts a single method on a single allowed route (`POST /v1/chat/completions`), substitutes the upstream `Authorization` header with the real provider secret, delivers unbuffered streaming server-sent events, and rejects all unauthorized routes.
- **Restricted Metrics Gate**: An allowlisting proxy that restricts outbound requests to specific public Grafana dashboard panel queries, blocking arbitrary external network access.
- **Host and Network Isolation**: Confines the untrusted agent container to an internal bridge network configured with isolated gateway mode (`com.docker.network.bridge.gateway_mode_ipv4: isolated`), preventing access to external networks and closing reachability to the host bridge interface.
- **Controlled Test Doubles and Automated Checks**: Synthetic doubles for the model provider upstream and Telegram Bot API, along with automated test targets executing from within the caged container to verify workflow completion and enforce security constraints.
- **Reproduction Package**: Pin declarations and clean build definitions enabling deterministic verification from source.
