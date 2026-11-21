# stack/host-provisioner — the host layer

Takes a bare-metal **Linux Mint (UI desktop)** install to a production-grade Hermes host: a documented
user, the directory standard, Hermes installed as a supervised user service, and every Hermes setting
applied as config-as-code.

**Status: v0.1.0 spec — not implemented.** There is no `install.sh` or `verify.sh` here yet. This
directory carries the specification a builder works from; nothing in it writes to a host.

| File | What it is |
|---|---|
| [`SPEC.v0.1.0.md`](SPEC.v0.1.0.md) | The spec: what done proves, what it does not, decisions, contract, risks. |
| [`elements.v1.yaml`](elements.v1.yaml) | The element register — every element with its external source, its foundation requirement, and the `verify.sh` check it needs. |

## The admission rule

Every element maps to a foundation requirement (`stack/foundation/requirements.v1.yaml`) **and** cites an
external source: upstream Hermes docs, a pinned repo, or a distribution/OS manual. A bespoke element is
admitted only with a recorded note that nothing existing covers it. *"Useful" is not a criterion.*

## Shape, once built

```
install.sh                          dry run by default; --apply writes; one sudo prompt
desired-state.v0.1.0.yaml           the values install.sh renders
host-provisioner-v0.1.0.lock.yaml   what it resolved to on the host it ran on
verify.sh                           one named check per element id; exit 0 = shippable
```

Same contract as `stack/bot-profile`, `stack/github-template` and `stack/mission-control`.

## What it will not do

Write a secret, generate a keypair, take a client checkout, or run anything as root that is not
`/etc/hermes/*` or `loginctl enable-linger`. Backup *content* and secret *values* belong to other
layers; this one creates the anchors and asserts the modes.
