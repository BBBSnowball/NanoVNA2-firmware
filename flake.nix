{
  #inputs.nanovna.url = github:nanovna-v2/NanoVNA2-firmware;
  #inputs.nanovna.flake = false;

  outputs = { nixpkgs, ... }: let
    foreachSystem = with builtins; f: listToAttrs (map (system: { name = system; value = f system; }) [ "x86_64-linux" "aarch64-linux" ]);
    forSystem = system: rec {
      nixpkgsFn = import nixpkgs;
      pkgs = nixpkgsFn { inherit system; };

      pkgsCross = nixpkgsFn {
        inherit system;
        crossSystem = pkgs.lib.systems.examples.arm-embedded;
        config.allowUnsupportedSystem = true;
      };

      pythonForUpload = pkgs.python3.withPackages (p: [ p.pyserial ]);

      devShell = pkgsCross.mkShell {
        nativeBuildInputs = with pkgsCross.pkgsBuildHost; [
          gcc binutils
          pythonForUpload
        ];
      };

      nanovna-src = {
        # matches date of prebuilt firmware but has compile errors
        #NOTE 32077fdd887ec03a1fd00adec58264037c7504dc is the release tag 20201013 but it is identical except for the LICENSE file.
        a.version = "20201013-24ccac";
        a.rev = "24ccacaf2ff67d88261841a0845528d2d1d2aa7a";  
        a.hash = "sha256-bjhoYIZUC5qLvLhdAJjuE7bpogTsBkCaMUHKzSMqibI=";

        # slightly newer than `a` and fixes a compile error
        # -> compiles but doesn't boot
        b.version = "20201017-669fab";
        b.rev = "669fab975c0ec064921825d7e5f297a0bbc6fc43";
        b.hash = "sha256-mA8FADQEREaWTRCMF+NLvx6tRLqMejsbKXGmgd1Jm2w=";

        # doesn't work for board-v2_2, it seems - at least when I build it
        c.version = "20210915-d9c768";
        c.rev = "d9c768b298677d2fecc98fb37ec9cd4395dc781e";
        c.hash = "sha256-oDOX6FWkQw+0oC70oQOfaHByAjuDWU848sALP8jYlaY=";
      };

      packages.nanovna2-firmware-boardv2_2-broken = pkgsCross.stdenv.mkDerivation rec {
        pname = "nanovna2-firmware";
        version = nanovna-src.b.version;

        passthru.src-info = {
          owner = "nanovna-v2";
          repo = "NanoVNA2-firmware";
          inherit (nanovna-src.b) rev hash;
          fetchSubmodules = true;
        };
        src = pkgs.fetchFromGitHub passthru.src-info;

        # get newer sources as well, for bootload_firmware.py script
        newSrc = pkgs.fetchFromGitHub {
          owner = "nanovna-v2";
          repo = "NanoVNA2-firmware";
          inherit (nanovna-src.c) rev hash;
          fetchSubmodules = true;
        };

        depsBuildBuild = [ pkgs.python3 ];

        BOARDNAME = "board_v2_2";
        EXTRA_CFLAGS = "-DSWEEP_POINTS_MAX=201 -DSAVEAREA_MAX=7";
        LDSCRIPT = "./gd32f303cc_with_bootloader.ld";

        postPatch = ''
          patchShebangs .
          #patchShebangs ./libopencm3/scripts/irq2nvic_h

          mkdir .git
          echo ${src.rev} >.git/HEAD
          touch .git/index

          # The subst would add an extra backslash at the end. We should use proper shell escaping here but fortunately, we know that the path won't have any special chars.
          substituteInPlace libopencm3/Makefile --replace 'SRCLIBDIR:= $(subst $(space),\$(space),$(realpath lib))' 'SRCLIBDIR:=$(realpath lib)'
        '';

        preBuild = ''
          # README mentions that the linker scripts might be overwritten by libopencm3 and indeed libopencm3/mk/genlink-rules.mk has a rule for that.
          # -> Doesn't happen for me (because all file times are identical, I assume) but let's make sure to avoid it.
          chmod -w "$LDSCRIPT"
          touch "$LDSCRIPT"

          # README suggests building with `-j4` but `-j8` fails for me (header is used before it is generated) so let's play it save.
          #makeFlagsArray+=(-j$NIX_BUILD_CORES)

          makeFlagsArray+=(BOARDNAME="$BOARDNAME" EXTRA_CFLAGS="$EXTRA_CFLAGS" LDSCRIPT=$LDSCRIPT)
          makeFlagsArray+=(GITVERSION="${passthru.src-info.rev}" GITURL="https://github.com/${passthru.src-info.owner}/${passthru.src-info.repo}.git")
          #makeFlagsArray+=(V=1)
        '';

        uploadScript = pkgs.writeScript "flash-nanovna2-firmware" ''
          fileArgs=(--file "@out@/share/nanovna2/binary.bin")
          for arg in "$@" ; do
            case "$arg" in
              -p|--printsn|-r|--reboot)
                # incompatible with --file so call it without
                fileArgs=()
                ;;
            esac
          done
          exec ${pythonForUpload}/bin/python @out@/share/nanovna2/bootload_firmware.py "''${fileArgs[@]}" "$@"
        '';

        installPhase = ''
          mkdir -p $out/bin $out/share/nanovna2
          cp ${newSrc}/bootload_firmware.py binary.{bin,elf,hex} $out/share/nanovna2/
          substitute ${uploadScript} $out/bin/flash-nanovna2-firmware-$BOARDNAME --subst-var out
          chmod +x $out/bin/flash-nanovna2-firmware-$BOARDNAME
        '';
      };

      # see https://nanorfe.com/nanovna-versions.html
      # We get no .elf, unfortunately.
      packages.nanovna2-firmware-boardv2_2-prebuilt-binary = pkgs.fetchurl {
        url = "https://nanorfe.com/downloads/20201013/nanovna-v2-20201013-v2_2.bin";
        hash = "sha256-rS6Dxxb/ewNb3UVDfjTZs4THiztafgRnJFSGHue8r6k=";
        passthru.version = "20201013";
      };

      packages.nanovna2-firmware-boardv2_2-prebuilt = pkgs.runCommand "nanovna2-firmware-boardv2_2-prebuilt" {
        binary = packages.nanovna2-firmware-boardv2_2-prebuilt-binary;
        BOARDNAME = "board_v2_2";

        newFirmwareSrc = pkgs.fetchFromGitHub {
          owner = "nanovna-v2";
          repo = "NanoVNA2-firmware";
          inherit (nanovna-src.c) rev hash;
          fetchSubmodules = false;
        };

        inherit pythonForUpload;

        uploadScript = pkgs.writeScript "flash-nanovna2-firmware" ''
          fileArgs=(--file "@out@/share/nanovna2/binary.bin")
          for arg in "$@" ; do
            case "$arg" in
              -p|--printsn|-r|--reboot)
                # incompatible with --file so call it without
                fileArgs=()
                ;;
            esac
          done
          exec ${pythonForUpload}/bin/python @out@/share/nanovna2/bootload_firmware.py "''${fileArgs[@]}" "$@"
        '';
      } ''
        mkdir -p $out/bin $out/share/nanovna2
        cp $newFirmwareSrc/bootload_firmware.py $out/share/nanovna2/
        cp $binary $out/share/nanovna2/binary.bin
        substitute $uploadScript $out/bin/flash-nanovna2-firmware-$BOARDNAME --subst-var out
        chmod +x $out/bin/flash-nanovna2-firmware-$BOARDNAME
      '';

      apps.flash-nanovna2-firmware-board_v2_2-broken = { type = "app"; program = "${packages.nanovna2-firmware-boardv2_2-broken}/bin/flash-nanovna2-firmware-board_v2_2"; };
      apps.flash-nanovna2-firmware-board_v2_2-prebuilt = { type = "app"; program = "${packages.nanovna2-firmware-boardv2_2-prebuilt}/bin/flash-nanovna2-firmware-board_v2_2"; };

      packages.nanovna-qt-src = pkgs.fetchFromGitHub {
        owner = "nanovna-v2";
        repo = "NanoVNA-QT";
        rev = "0aa6ee4e68ade0285755f06c2eab240e2d0beea1";
        hash = "sha256-xnIDpp9gIAK5KKVUF5Jy9NSp6JiNbK3PBuCb5fdKzTg=";
        passthru.version = "20220301-0aa6ee";
        #rev = "cb891507b9794a4d9ea4694d870c7934b84cabd1";  # tag 20200507
      };

      packages.libxavna = pkgs.stdenv.mkDerivation {
        pname = "libxavna";
        version = packages.nanovna-qt-src.passthru.version;
        src = packages.nanovna-qt-src;

        nativeBuildInputs = with pkgs; [ automake libtool autoreconfHook ];
        buildInputs = with pkgs; [ eigen fftw ];

        postInstall = ''
          cp -r libxavna/include $out/include
        '';
      };

      packages.libxavna-mock-ui = pkgs.stdenv.mkDerivation {
        pname = "libxavna";
        version = packages.nanovna-qt-src.passthru.version;
        src = packages.nanovna-qt-src;

        nativeBuildInputs = with pkgs; [ automake libtool autoreconfHook libsForQt5.qmake libsForQt5.wrapQtAppsHook ];
        buildInputs = with pkgs; [ packages.libxavna eigen fftw libsForQt5.qt5.qtcharts ];

        preConfigure = ''
          cd libxavna/xavna_mock_ui
          substituteInPlace xavna_mock_ui.pro --replace 'target.path = /usr/lib' "target.path = $out/lib"
        '';
      };

      packages.nanovna-qt = pkgs.stdenv.mkDerivation {
        pname = "nanovna-qt";
        version = packages.nanovna-qt-src.passthru.version;
        src = packages.nanovna-qt-src;

        nativeBuildInputs = with pkgs; [ automake libtool autoreconfHook libsForQt5.qmake libsForQt5.wrapQtAppsHook wrapGAppsHook ];
        buildInputs = with pkgs; [ eigen fftw libsForQt5.qt5.qtcharts packages.libxavna packages.libxavna-mock-ui ];

        preConfigure = ''
          cd vna_qt
          substituteInPlace main.C --replace 'load("languages/vna_qt_"' 'load("'$out'/share/vna_qt/languages/vna_qt_"'
        '';

        installPhase = ''
          mkdir -p $out/bin $out/share/vna_qt/
          cp vna_qt $out/bin/
          cp -r languages $out/share/vna_qt/
        '';
      };

      #NOTE You might want to use nanovna-saver, instead.
      apps.nanovna-qt = { type = "app"; program = "${packages.nanovna-qt}/bin/vna_qt"; };

      # This one is already packaged - not much to do here but let's add it here to have it "at hand".
      packages.nanovna-saver = pkgs.nanovna-saver.overrideAttrs (old: {
        # avoid this error when saving calibration data:
        # (python3.9:1395821): GLib-GIO-ERROR **: 19:09:47.752: Settings schema 'org.gtk.Settings.FileChooser' is not installed
        # -> nanovna-saver already uses gappsWrapperArgs in its preFixup but it doesn't add wrapGAppsHook as a dependency
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkgsBuildHost.wrapGAppsHook ];
        # wrapGAppsHook should add at least one of these but that doesn't seem to work
        buildInputs = with pkgs; [
          dconf.lib
          gtk3
        ];
      });
      apps.nanovna-saver = { type = "app"; program = "${packages.nanovna-saver}/bin/NanoVNASaver"; };
    };
    bySystem = foreachSystem forSystem;
  in {
    devShell = foreachSystem (system: bySystem.${system}.devShell);
    packages = foreachSystem (system: bySystem.${system}.packages);
    apps = foreachSystem (system: bySystem.${system}.apps);
  };
}
