{ config, lib, pkgs, ... }:

with lib;

let

cfg = config.services.tlp;

enableRDW = config.networking.networkmanager.enable;

tlp = pkgs.tlp.override {
  inherit enableRDW;
  kmod = config.system.sbin.modprobe;
};

# XXX: We can't use writeTextFile + readFile here because it triggers
# TLP build to get the .drv (even on --dry-run).
confFile = pkgs.runCommand "tlp"
  { config = cfg.extraConfig;
    passAsFile = [ "config" ];
  }
  ''
    cat ${tlp}/etc/default/tlp > $out
    cat $configPath >> $out
  '';

in

{

  ###### interface

  options = {

    services.tlp = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable the TLP daemon.";
      };

      extraConfig = mkOption {
        type = types.str;
        default = "";
        description = "Additional configuration variables for TLP";
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    systemd.services = {
      tlp = {
        description = "TLP system startup/shutdown";

        after = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];
        before = [ "shutdown.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tlp}/bin/tlp init start";
          ExecStop = "${tlp}/bin/tlp init stop";
        };
      };

      tlp-sleep = {
        description = "TLP suspend/resume";

        wantedBy = [ "sleep.target" ];
        before = [ "sleep.target" ];

        unitConfig = {
          StopWhenUnneeded = true;
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tlp}/bin/tlp suspend";
          ExecStop = "${tlp}/bin/tlp resume";
        };
      };
    };

    services.udev.packages = [ tlp ];

    environment.etc = [{ source = confFile;
                         target = "default/tlp";
                       }
                      ] ++ optional enableRDW {
                        source = "${tlp}/etc/NetworkManager/dispatcher.d/99tlp-rdw-nm";
                        target = "NetworkManager/dispatcher.d/99tlp-rdw-nm";
                      };

    environment.systemPackages = [ tlp ];

    boot.kernelModules = [ "msr" ];

  };

}
