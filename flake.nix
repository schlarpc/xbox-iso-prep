{
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable"; };
  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      xbedump = pkgs.stdenv.mkDerivation rec {
        pname = "xbedump";
        version = "b8cd5cd0";
        src = pkgs.fetchFromGitHub {
          owner = "XboxDev";
          repo = pname;
          rev = version;
          sha256 = "1h3966qzpskfbd9rv578c3w0yvkpxf8msv7aq6dinv9arf35njk1";
        };
        buildPhase = ''
          make
        '';
        installPhase = ''
          mkdir -p $out/bin
          mv xbe $out/bin
        '';
        meta.license = pkgs.lib.licenses.gpl2Plus;
      };

      sign-xbe = pkgs.writeShellScript "sign-xbe" ''
        set -euxo pipefail

        TMPDIR=$(mktemp -d --suffix=.sign-xbe)
        trap 'rm -rf "$TMPDIR"' EXIT

        OUTPUT_ABSOLUTE_PATH="$(realpath -m "''${2:-$1}")"

        cp "$1" "$TMPDIR/input.xbe"
        cd "$TMPDIR"
        ${xbedump}/bin/xbe input.xbe -habibi
        cp out.xbe "$OUTPUT_ABSOLUTE_PATH"
      '';

      xbox-iso-loader-patch = pkgs.stdenv.mkDerivation rec {
        pname = "xbox-iso-loader-patch";
        version = "cfdd0961";
        src = pkgs.fetchFromGitHub {
          owner = "schlarpc";
          repo = pname;
          rev = version;
          hash = "sha256-9S2ilAfnKIqqwLTxa7pzTYdRV97CkDJnqVV1ZlFByg0=";
        };
        nativeBuildInputs = [ pkgs.nasm xbedump ];
        patchPhase = ''
          substituteInPlace xboxapp.asm \
              --replace \
                  ';;;%define BOOT_TO_DASH' \
                  '%define BOOT_TO_DASH' \
              --replace \
                  "%define DASH_PATH   '\Device\Harddisk0\Partition1\default.xbe'" \
                  "%define DASH_PATH '\Device\Harddisk0\Partition1\XBMC\default.xbe'"
        '';
        buildPhase = ''
          nasm -O0 -o patcher.xbe xboxapp.asm
          ${sign-xbe} patcher.xbe
        '';
        installPhase = ''
          mv patcher.xbe $out
        '';
        meta.license = pkgs.lib.licenses.gpl2;
      };

      extract-xiso = pkgs.stdenv.mkDerivation rec {
        pname = "extract-xiso";
        version = "v2.7.1-20-g9c0f479"; # includes XGD repacking
        src = pkgs.fetchFromGitHub {
          owner = "XboxDev";
          repo = pname;
          rev = version;
          sha256 = "1sq0vgr6pj6ha4vv6v8728byzmj0q0yn242him034ydj4h9zx1zj";
        };
        buildInputs = [ pkgs.cmake ];
        configurePhase = ''
          cmake .
        '';
        buildPhase = ''
          make
        '';
        installPhase = ''
          mkdir -p $out/bin
          mv extract-xiso $out/bin
        '';

        meta.license = pkgs.lib.licenses.bsdOriginal;
      };

      repack-xiso = pkgs.writeShellScript "repack-xiso" ''
        set -euxo pipefail

        TMPDIR=$(mktemp -d --suffix=.repack-xiso)
        trap 'rm -rf "$TMPDIR"' EXIT

        INPUT_ABSOLUTE_PATH="$(realpath "$1")"
        OUTPUT_BASENAME="$(basename "$2")"
        OUTPUT_DIRECTORY="$(dirname "$(realpath -m "$2")")"

        ln -s "$INPUT_ABSOLUTE_PATH" "$TMPDIR/$OUTPUT_BASENAME"
        ${extract-xiso}/bin/extract-xiso -r "$TMPDIR/$OUTPUT_BASENAME" -d "$OUTPUT_DIRECTORY"
      '';

      split-xiso = pkgs.writeShellScript "split-xiso" ''
        set -euxo pipefail
        OUTPUT_PATH="''${2:-.}"
        ${pkgs.coreutils}/bin/split \
            --bytes=3999M --numeric-suffixes=1 --suffix-length=1 --additional-suffix=.iso \
            "$1" "$OUTPUT_PATH/$(${pkgs.coreutils}/bin/basename "$1" .iso).part"
      '';

      driveimageutils = pkgs.pkgsi686Linux.stdenv.mkDerivation rec {
        pname = "driveimageutils";
        version = "1.0.1";
        src = pkgs.fetchzip {
          url = pkgs.lib.concatStringsSep "/" [
            "https://the-eye.eu/public/xbins"
            "XBOX/Console%20Based%20Applications/exploits/Bios%20Patchers%20and%20Loaders"
            "nkpatcher/${pname}/${pname}-v${version}.zip"
          ];
          sha256 = "0mls3s54svlmbrkw7rpjmgl1rx0nq0z0nyp60x48n8v39fjpgr2d";
        };

        nativeBuildInputs = [ pkgs.nasm xbedump ];

        NIX_CFLAGS_COMPILE = pkgs.lib.concatStringsSep " " [
          "-Wno-error"
          "-fno-builtin"
          "-fno-pie"
          "-fno-stack-protector"
          "-fomit-frame-pointer"
          "-fno-exceptions"
          "-fno-asynchronous-unwind-tables"
          "-fno-unwind-tables"
          "-fno-common"
        ];

        prePatch = ''
          substituteInPlace src/Makefile --replace -mcpu -mtune
          substituteInPlace src/Makefile --replace /bin/pwd ${pkgs.coreutils}/bin/pwd
          substituteInPlace src/strh.h --replace size_t SIZE_T
          substituteInPlace src/strh.c --replace size_t SIZE_T
          substituteInPlace src/ldscript.ld --replace '*(.rodata)' '*(.rodata*)'
          # XBMC's title extraction is bugged: https://www.xbmc4xbox.org.uk/forum/viewtopic.php?t=8383
          substituteInPlace src/ldscript.ld \
              --replace '/* Image header */' '/* Image header */ image_header = ABSOLUTE(.);' \
              --replace 'image_header_size = .' 'image_header_size = ABSOLUTE(.) - image_header'
          cat src/ldscript.ld
        '';

        buildPhase = ''
          cd src
          make attach.xbe detach.xbe
          ${sign-xbe} attach.xbe
          ${sign-xbe} detach.xbe
        '';

        installPhase = ''
          mkdir $out
          cp *.xbe $out
        '';

        meta.license = pkgs.lib.licenses.gpl2Plus;
      };

      xbfuse = pkgs.stdenv.mkDerivation rec {
        pname = "xbfuse";
        version = "967a44f3";
        src = pkgs.fetchFromGitHub {
          owner = "multimediamike";
          repo = pname;
          rev = version;
          hash = "sha256-9+Xh4NCiLM2c/5bg5W/5d4rN4Xfx7KvjQEW9JHvDuz0=";
        };
        nativeBuildInputs = [ pkgs.autoreconfHook pkgs.pkg-config ];
        buildInputs = [ pkgs.fuse ];
        meta.license = pkgs.lib.licenses.gpl2Plus;
      };

      extract-xiso-default-xbe =
        pkgs.writeShellScript "extract-xiso-default-xbe" ''
          set -euxo pipefail

          TMPDIR=$(mktemp -d --suffix=.extract-xiso-default-xbe)
          trap 'fusermount -u "$TMPDIR" || true; rm -rf "$TMPDIR"' EXIT

          ${xbfuse}/bin/xbfuse "$1" "$TMPDIR"

          # find file case-insensitive-ly
          DEFAULT_XBE="$(find "$TMPDIR" -maxdepth 1 -type f -iname default.xbe -print)"
          # cp gives a weird "failed to extend" error here, xbfuse bug?
          cat "$DEFAULT_XBE" > "$2"
        '';

      extra-python-libs = ps:
        with ps;
        [
          (buildPythonPackage rec {
            pname = "pyxbe";
            version = "a7ae1bb2";
            src = pkgs.fetchFromGitHub {
              owner = "mborgerson";
              repo = pname;
              rev = version;
              hash = "sha256-V0RewgzufSumBsg1Vs4WQXeLkZrQmhv/OhL9QFxR6bI=";
            };
            doCheck = false;
            meta.license = pkgs.lib.licenses.mit;
          })
        ];

      transplant-xbe-metadata = pkgs.writeScript "transplant-xbe-metadata" ''
        #!${pkgs.python3.withPackages extra-python-libs}/bin/python3
        # this copies all user-recognizable metadata from one XBE into another:
        # title ID, name, alt title IDs, media types, region, ratings, disk number, version, icon

        import xbe
        import argparse
        import pathlib
        import os
        import shutil
        import tempfile


        class Xbe(xbe.Xbe):
            def vaddr_to_file_offset(self, addr):
                # pyxbe chokes on XBEs with no "logo", which is defined by a logo addr of 0
                # this is a dirty hack that probably works
                if addr == 0:
                    return 0
                return super().vaddr_to_file_offset(addr)

            def _init_from_data(self, data):
                # some games (example: Metal Slug 4 [USA]) are fubared and it's actually not
                # important for me to figure out why since I'm just trying to grab the metadata
                try:
                    super()._init_from_data(data)
                except Exception:
                    xbe.log.exception("Exception occured during parse, object is corrupted")


        def get_args():
            parser = argparse.ArgumentParser()
            parser.add_argument("source", type=pathlib.Path)
            parser.add_argument("destination", type=pathlib.Path)
            return parser.parse_args()


        def main():
            args = get_args()

            with args.source.open("rb") as source:
                source_xbe = Xbe(source.read())
            with args.destination.open("rb") as destination:
                destination_xbe = Xbe(destination.read())

            cert_attributes = (
                "title_id",
                "title_name",
                "title_alt_ids",
                "allowed_media",
                "region",
                "ratings",
                "disc_num",
                "version",
            )

            for cert_attribute in cert_attributes:
                setattr(
                    destination_xbe.cert,
                    cert_attribute,
                    getattr(source_xbe.cert, cert_attribute),
                )
            if "$$XTIMAGE" in source_xbe.sections:
                destination_xbe.sections["$$XTIMAGE"] = source_xbe.sections["$$XTIMAGE"]

            destination_resolved = args.destination.resolve()
            with tempfile.TemporaryDirectory(suffix="transplant-xbe-metadata") as tempdir:
                os.chdir(tempdir)
                destination_xbe.pack()
                shutil.move(pathlib.Path(tempdir) / "out.xbe", destination_resolved)


        if __name__ == "__main__":
            main()
      '';

      prepare-xiso = pkgs.writeShellScript "prepare-iso" ''
        set -euxo pipefail

        INPUT_FILE="$1"
        # sanitize directory name to FATX standards
        OUTPUT_PATH="$2/$(basename "$INPUT_FILE" .iso | tr -cs '[:alnum:] \n[]!#$%&'"'"'().@^_`{}~-' '_' | cut -c -42)"

        mkdir -p "$OUTPUT_PATH"

        ${repack-xiso} "$INPUT_FILE" "$OUTPUT_PATH/disk.iso"

        ${extract-xiso-default-xbe} "$OUTPUT_PATH/disk.iso" "$OUTPUT_PATH/original.xbe"
        cp --no-preserve=mode "${driveimageutils}/attach.xbe" "$OUTPUT_PATH/default.xbe"
        ${transplant-xbe-metadata} "$OUTPUT_PATH/original.xbe" "$OUTPUT_PATH/default.xbe"

        ${split-xiso} "$OUTPUT_PATH/disk.iso" "$OUTPUT_PATH"

        rm "$OUTPUT_PATH/disk.iso" "$OUTPUT_PATH/original.xbe"
      '';

      output-symlinks = pkgs.linkFarm "xbox-iso-loader" [
        {
          name = "prepare-xiso";
          path = prepare-xiso;
        }
        {
          name = "patcher.xbe";
          path = xbox-iso-loader-patch;
        }
      ];

    in { defaultPackage.x86_64-linux = output-symlinks; };
}
