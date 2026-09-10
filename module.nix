{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.supermemory;

  opt = lib.mkOption;
  types = lib.types;

  providerOption = {
    enable = lib.mkEnableOption "this LLM provider";
    apiKey = opt {
      type = types.nullOr types.str;
      default = null;
      description = "API key for this provider.";
    };
    baseUrl = opt {
      type = types.nullOr types.str;
      default = null;
      description = "Optional base URL override (OpenAI-compatible endpoints).";
    };
    model = opt {
      type = types.nullOr types.str;
      default = null;
      description = "Optional model name override.";
    };
  };

  env = lib.filterAttrs (_: v: v != null) (lib.listToAttrs (
    [
      { name = "PORT"; value = toString cfg.port; }
      { name = "SUPERMEMORY_DATA_DIR"; value = cfg.dataDir; }
      { name = "SUPERMEMORY_EMBEDDING_PROVIDER"; value = cfg.embeddings.provider; }
      { name = "SUPERMEMORY_EMBEDDING_MODEL"; value = cfg.embeddings.model; }
      { name = "SUPERMEMORY_EMBEDDING_DIMENSIONS"; value = toString cfg.embeddings.dimensions; }
    ]
    ++ lib.optionals (cfg.embeddings.ramLimit != null) [
      { name = "SUPERMEMORY_EMBEDDING_RAM_LIMIT"; value = cfg.embeddings.ramLimit; }
    ]
    # OpenAI / OpenAI-compatible
    ++ lib.optionals cfg.openai.enable (
      [
        { name = "OPENAI_API_KEY"; value = cfg.openai.apiKey; }
      ]
      ++ lib.optionals (cfg.openai.baseUrl != null) [ { name = "OPENAI_BASE_URL"; value = cfg.openai.baseUrl; } ]
      ++ lib.optionals (cfg.openai.model != null) [ { name = "OPENAI_MODEL"; value = cfg.openai.model; } ]
    )
    # Hosted providers
    ++ lib.optionals cfg.gemini.enable [ { name = "GEMINI_API_KEY"; value = cfg.gemini.apiKey; } ]
    ++ lib.optionals cfg.anthropic.enable [ { name = "ANTHROPIC_API_KEY"; value = cfg.anthropic.apiKey; } ]
    ++ lib.optionals cfg.groq.enable [ { name = "GROQ_API_KEY"; value = cfg.groq.apiKey; } ]
  ));
in
{
  options.services.supermemory = {
    enable = lib.mkEnableOption "supermemory, the self-hostable AI memory layer";

    package = opt {
      type = types.package;
      default = pkgs.supermemory-server;
      defaultText = lib.literalExpression "pkgs.supermemory-server";
      description = "The supermemory-server package to run.";
    };

    port = opt {
      type = types.port;
      default = 6767;
      description = "TCP port the server listens on.";
    };

    dataDir = opt {
      type = types.path;
      default = "/var/lib/supermemory";
      description = ''
        Directory where the database lives — documents, vectors and the
        encrypted config. The state persists across reboots: the default
        location is managed by systemd's StateDirectory (survives restarts
        and firmware updates), and custom paths are created on boot with the
        right ownership. Point this at a persistent mount (e.g. a ZFS/btrfs
        dataset) to keep the DB on separate storage.
      '';
    };

    user = opt {
      type = types.str;
      default = "supermemory";
      description = "System user the service runs as.";
    };

    group = opt {
      type = types.str;
      default = "supermemory";
      description = "System group the service runs as.";
    };

    openFirewall = lib.mkEnableOption "opening port 6767 in the firewall";

    environmentFile = opt {
      type = types.nullOr types.path;
      default = null;
      description = "Environment file (Key=Value lines) added to the systemd unit. Useful for secrets.";
    };

    extraEnvironment = opt {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to the service.";
    };

    openai = opt {
      type = types.submodule providerOption;
      default = { };
      description = "OpenAI or any OpenAI-compatible endpoint (Ollama, vLLM, LM Studio, a local proxy…). Set apiKey = \"dummy\" when pointing baseUrl at a local endpoint.";
    };

    gemini = opt {
      type = types.submodule providerOption;
      default = { };
      description = "Google Gemini provider.";
    };

    anthropic = opt {
      type = types.submodule providerOption;
      default = { };
      description = "Anthropic provider.";
    };

    groq = opt {
      type = types.submodule providerOption;
      default = { };
      description = "Groq provider.";
    };

    embeddings = opt {
      description = "Embedding backend configuration. Defaults to local CPU inference (no API key).";
      default = { };
      type = types.submodule {
        provider = opt {
          type = types.enum [
            "local"
            "openai"
            "gemini"
            "ollama"
          ];
          default = "local";
          description = "Embedding backend.";
        };
        model = opt {
          type = types.str;
          default = "Xenova/bge-base-en-v1.5";
          description = "Embedding model name.";
        };
        dimensions = opt {
          type = types.ints.positive;
          default = 768;
          description = "Embedding vector width; must match the model.";
        };
        ramLimit = opt {
          type = types.nullOr types.str;
          default = null;
          description = "Ingest memory budget, e.g. \"2gb\". Unset = server default.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.supermemory = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      shell = "/run/current-system/sw/bin/nologin";
    };

    users.groups.supermemory = { };

    systemd.tmpfiles.rules =
      lib.optional (cfg.dataDir != "/var/lib/supermemory")
        "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -";

    systemd.services.supermemory = {
      description = "Supermemory memory server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "network.target"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        # Wait for the filesystem holding the DB path to be mounted so the
        # database survives reboots even on a separate persistent volume.
        RequiresMountsFor = cfg.dataDir;
        ExecStart = "${lib.getExe cfg.package}";
        Restart = "on-failure";
        RestartSec = "3s";
        LimitNOFILE = 8192;
      } // lib.optionalAttrs (cfg.dataDir == "/var/lib/supermemory") {
        StateDirectory = "supermemory";
      } // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };

      environment = env // cfg.extraEnvironment;
    };

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}