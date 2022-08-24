{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader = {
    grub = {
      enable = true;
      device = "nodev";  # or "nodev" for efi only
      # efiSupport = true;
      configurationLimit = 20;
    };
    efi = {
      canTouchEfiVariables = true;
      # efiSysMountPoint = "/boot/efi";
    };
  };

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "America/New_York";

  # Select internationalization properties.
  i18n.defaultLocale = "en_US.utf8";
  i18n.extraLocaleSettings.LC_TIME = "en_DK.UTF-8"; # ISO-8601 time

  users.users.adjacentresearch = {
    isNormalUser = true;
    shell = pkgs.bash;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
      keep-outputs = true
    '';
    settings.auto-optimise-store = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    # autoUpgrade = {
    #   enable = true;
    #   flake = "~/nixos";
    #   flags = [ "--update-input" "nixpkgs" "--commit-lock-file" ];
    # };
  };

  fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      nerdfonts # (nerdfonts.override { fonts = [ "Iosevka" "Meslo" ]; })
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # programming
    rustc
    cargo
    docker
    docker-compose

    # tools
    wget
    btop
    htop
    ripgrep
    exa
    bat
    fd
    git
    vim
    ncdu

    # system tools and monitoring   
    fail2ban
    promtail
    prometheus-alertmanager
  ];

  environment.sessionVariables = {
    XDG_CONFIG_HOME = "$HOME/.config";
    NIXOS_OZONE_WL = "1";
  };

  security.sudo = {
    package = pkgs.sudo.override {
      withInsults = true;
    };
    extraConfig = "Defaults insults";
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    ignoreIP = [
      "127.0.0.0/8"
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
      "8.8.8.8"
    ];
  };

  services.grafana = {
    enable   = true;
    port     = 3000;
    domain   = "localhost";
    protocol = "http";
    dataDir  = "/var/lib/grafana";
    provision = {
        enable = true;
        datasources = [
          {
            type = "loki";
            name = "Loki";
            url = "http://127.0.0.1:3030";
            jsonData.maxLines = 1000;
          }
          { 
            type = "prometheus";
            name = "Prometheus";
            url = "http://127.0.0.1:9090";
          }
          {
            type = "prometheus-alertmanager";
            name = "Prometheus Alertmanager";
            url = "http://localhost:9093";
          }
        ];

        dashboards = [
          {
            name = "tf-declared-dashboards";
            options.path = "/etc/nixos/grafana/dashboards";
          }
        ];
    };
  };

  # nginx reverse proxy
  services.nginx.virtualHosts.${config.services.grafana.domain} = {
    locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.port}";
        proxyWebsockets = true;
    };
  };

  services.prometheus = {
      enable = true;
      port = 9090;

      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
          port = 9002;
        };
      };

      scrapeConfigs = [
        {
          job_name = "adjacent";
          static_configs = [{
            targets = [ "127.0.0.1:9002" ];
          }];
        }
      ];

    ruleFiles = [
      (pkgs.writeText "prometheus-rules.yml" (builtins.toJSON {
        groups = [
          {
            name = "alerting-rules";
            rules = import ./alert-rules.nix {inherit lib;};
          }
        ];
      }))
    ];

    alertmanagers = [{
      scheme = "http";
      static_configs = [{
        targets = ["127.0.0.1:9093"];
      }];
    }];

    alertmanager = {
      enable = true;
      configuration = {
        route = {
          receiver = "telegram";
          group_wait = "30s";
          group_interval = "1m";
          group_by = [ "alertname" ];
        };
        receivers = [{
          name = "telegram";
           telegram_configs = [{
            api_url = "https://api.telegram.org";
            bot_token = <string>;
            chat_id = <int>;
            # message = "";
            parse_mode = "HTML";
          }];
        }];
      };
    };
 };

  services.loki = {
    enable = true;
    configuration = {
      server.http_listen_port = 3030;
      auth_enabled = false;

      ingester = {
        lifecycler = {
          address = "127.0.0.1";
          ring = {
            kvstore = {
              store = "inmemory";
            };
            replication_factor = 1;
          };
        };
        chunk_idle_period = "1h";
        max_chunk_age = "1h";
        chunk_target_size = 999999;
        chunk_retain_period = "30s";
        max_transfer_retries = 0;
      };

      schema_config = {
        configs = [{
          from = "2022-06-06";
          store = "boltdb-shipper";
          object_store = "filesystem";
          schema = "v11";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];
      };

      storage_config = {
        boltdb_shipper = {
          active_index_directory = "/var/lib/loki/boltdb-shipper-active";
          cache_location = "/var/lib/loki/boltdb-shipper-cache";
          cache_ttl = "24h";
          shared_store = "filesystem";
        };

        filesystem = {
          directory = "/var/lib/loki/chunks";
        };
      };

      limits_config = {
        reject_old_samples = true;
        reject_old_samples_max_age = "168h";
      };

      chunk_store_config = {
        max_look_back_period = "0s";
      };

      table_manager = {
        retention_deletes_enabled = false;
        retention_period = "0s";
      };

      compactor = {
        working_directory = "/var/lib/loki";
        shared_store = "filesystem";
        compactor_ring = {
          kvstore = {
            store = "inmemory";
          };
        };
      };

     ruler = {
        enable_api = true;
        enable_alertmanager_v2 = true;
        alertmanager_url = "http://127.0.0.1:9093";
        ring.kvstore.store = "inmemory";
        rule_path = "/var/lib/loki/rules-temp";
        storage = {
          type = "local";
          local.directory = "/var/lib/loki/rules";
        };
      };
    };
  };

  systemd.services.promtail = {
    description = "Promtail service for Loki";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = ''
        ${pkgs.grafana-loki}/bin/promtail --config.file ${./promtail.yaml}
      '';
    };
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  system.stateVersion = "22.05";
}   
