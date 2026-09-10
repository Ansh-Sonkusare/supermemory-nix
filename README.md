# supermemory-nix

[Nix](https://nixos.org) package + [NixOS](https://nixos.org) service module for [supermemory-server](https://github.com/supermemoryai/supermemory) — the self-hostable AI memory layer.

- **Package** — `supermemory-server` v0.0.8 for `aarch64-linux`, `x86_64-linux`, `aarch64-darwin`, `x86_64-darwin`
- **NixOS module** — one declarative `services.supermemory` block: LLM provider, local embeddings, persistent DB path, firewall, secrets
- Local CPU embeddings out of the box (`Xenova/bge-base-en-v1.5`) — no embedding API key needed
- Fully offline with Ollama / any OpenAI-compatible endpoint on your machine

## Usage (flake)

```nix
{
  inputs.supermemory-nix.url = "github:Ansh-Sonkusare/supermemory-nix";

  outputs = { self, nixpkgs, supermemory-nix }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        # makes pkgs.supermemory-server available
        supermemory-nix.overlays.default
        supermemory-nix.nixosModules.supermemory
        {
          services.supermemory = {
            enable = true;
            openai = {
              enable = true;
              apiKey = "dummy";
              baseUrl = "http://127.0.0.1:20128/v1"; # Ollama / vLLM / LM Studio / proxy
              model = "free-first";
            };
          };
        }
      ];
    };
  };
}
```

```console
$ nixos-rebuild switch --flake .#myhost
```

## Trying the package ad hoc

```console
$ nix run github:Ansh-Sonkusare/supermemory-nix -- --help
```

or pin the binary in your dev shell:

```nix
{
  inputs.supermemory-nix.url = "github:Ansh-Sonkusare/supermemory-nix";
  outputs = { supermemory-nix, ... }: {
    devShells.default = pkgs.mkShell {
      packages = [ supermemory-nix.packages.${pkgs.system}.supermemory-server ];
    };
  };
}
```

The server reads its config from the environment; set `OPENAI_API_KEY`
(e.g. `dummy` for a local endpoint), `OPENAI_BASE_URL`, `OPENAI_MODEL`,
`GEMINI_API_KEY`, `ANTHROPIC_API_KEY` or `GROQ_API_KEY` and start it — it
serves on `http://localhost:6767`.

## Service module options

| Option | Default | Description |
|---|---|---|
| `services.supermemory.enable` | `false` | Enable the systemd service. |
| `services.supermemory.package` | `pkgs.supermemory-server` | Binary to run (works with the overlay). |
| `services.supermemory.port` | `6767` | TCP port. |
| `services.supermemory.dataDir` | `/var/lib/supermemory` | **Database path.** Persists across reboots: the default is a systemd `StateDirectory` (survives restarts and updates); a custom path is created on boot with the right ownership and the service waits for its filesystem (`RequiresMountsFor`) — point it at a ZFS/btrfs dataset or another persistent mount. |
| `services.supermemory.user` | `supermemory` | Service user (created automatically). |
| `services.supermemory.group` | `supermemory` | Service group (created automatically). |
| `services.supermemory.openFirewall` | `false` | Open the port in `networking.firewall`. |
| `services.supermemory.environmentFile` | `null` | systemd `EnvironmentFile` for secrets (API keys) kept out of the Nix store. |
| `services.supermemory.extraEnvironment` | `{}` | Extra env vars passed to the service. |
| `services.supermemory.openai.*` | disabled | `{ enable, apiKey, baseUrl, model }` — OpenAI or any OpenAI-compatible endpoint. |
| `services.supermemory.gemini.*` | disabled | `{ enable, apiKey, baseUrl, model }`. |
| `services.supermemory.anthropic.*` | disabled | `{ enable, apiKey, baseUrl, model }`. |
| `services.supermemory.groq.*` | disabled | `{ enable, apiKey, baseUrl, model }`. |
| `services.supermemory.embeddings.provider` | `local` | `local`, `openai`, `gemini` or `ollama`. |
| `services.supermemory.embeddings.model` | `Xenova/bge-base-en-v1.5` | Embedding model. |
| `services.supermemory.embeddings.dimensions` | `768` | Vector width; must match the model. |
| `services.supermemory.embeddings.ramLimit` | `null` | Ingest memory budget, e.g. `"2gb"`. |

### Local LLM (fully offline) on NixOS

```nix
services.supermemory = {
  enable = true;
  openai = {
    enable = true;
    apiKey = "dummy";
    baseUrl = "http://127.0.0.1:20128/v1";
    model = "free-first";
  };
  # keep your DB on a persistent dataset
  dataDir = "/mnt/zfs/supermemory";
  openFirewall = true;
};
```

### Secrets via environmentFile

```nix
services.supermemory = {
  enable = true;
  environmentFile = config.age.secrets.supermemoryEnv.path; # or a plain path
  gemini.enable = true;
};
```

Secrets stay out of the Nix store. The API key gets its own `GEMINI_API_KEY`
line in the environment file.

## First boot

The server prints its API key once to the journal on startup; it's
auto-applied for unauthenticated `localhost` requests:

```console
$ journalctl -u supermemory | grep 'api key'
```

Use it as a Bearer token for the `/v3` and `/v4` APIs, e.g.
`curl -H "Authorization: Bearer sm_…" http://localhost:6767/v3/health`.

## How it's packaged

`package.nix` fetches the upstream release binary from
`github.com/supermemoryai/supermemory/releases` for the exact architecture
and verifies it against the upstream-published SHA-256. On Linux the binary
is glibc-linked, so `autoPatchelfHook` re-points its interpreter at the Nix
store glibc. CA certs come from the system; the embedding model is bundled
in the binary (local CPU inference).

Upstream binariaries are "lite"-licensed up to 10k documents.

## Updating the pinned version

```console
$ nix flake update nixpkgs
$ ./scripts/bump-version.sh 0.0.9   # if you add one
```

Or hand-edit: bump `version` in `package.nix`, replace the four `hash`
values with the `.sha256` files published on the release.

## License

MIT — see [`LICENSE`](./LICENSE). The upstream supermemory binary has its own
license.