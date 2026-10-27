{ lib
, stdenvNoCC
, fetchurl
, dpkg
, makeWrapper
# ---- runtime libraries the vendored Qt5 app does NOT bundle ----
, glibc
, gcc
, alsa-lib
, dbus
, libdrm
, expat
, fontconfig
, freetype
, glib
, libgudev
, xz
, nspr
, nss
, opus
, pixman
, pulseaudio
, sqlite
, libuuid
, v4l-utils
, mesa
, zlib
, libx11        # also provides libX11-xcb.so.1
, libxcb
, libxext
, libxfixes
, libxi
, libxrandr
, libxrender
, libxscrnsaver  # provides libXss.so.1
, libxcomposite
, libxcursor
, libxdamage
, libxslt
# ---- vendor deb ----
, srcUrl ? "file:///home/test/Code/nixpackage/CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb"
, srcHash ? "sha256-61840ae48b70133844327c400da6f25fab1bf7f477225fccb319ff14df19f18a"
}:

# 天翼云电脑 (CTyun Cloud PC / "AI 云电脑") desktop client.
#
# The vendor ships a Debian binary package (ctyunclouddeskpublic) whose payload
# is a self-contained Qt5 + QtWebEngine application under
# /opt/ctg/CtyunClouddeskPublic plus two system daemons. We:
#   1. extract the data payload with dpkg-deb (no maintainer scripts run here),
#   2. preserve the vendor directory layout so relative lookups keep working
#      (RPATH=$ORIGIN/lib, ../plugins, ../qml),
#   3. re-point the .desktop Exec/Icon at absolute store paths,
#   4. wrap the entry-point binaries so the handful of system libraries the
#      bundle is missing are always resolvable.
#
# The vendor maintainer scripts (preinst/postinst/postrm) are NOT run; their
# effects are reproduced declaratively by the NixOS module (see nixos/).
stdenvNoCC.mkDerivation rec {
  pname = "ctyunclouddeskpublic";
  version = "4.1.0.1346";

  src = fetchurl {
    url = srcUrl;
    inherit srcHash;
  };

  nativeBuildInputs = [ dpkg makeWrapper ];

  # Vendor payload is prebuilt; nothing to compile or check.
  dontConfigure = true;
  dontBuild = true;
  doCheck = false;

  installPhase = ''
    runHook preInstall

    # Extract the data payload only (control scripts are handled by the
    # NixOS module, see docs/deb-analysis.md).
    dpkg-deb -x "$src" "$TMPDIR/payload"

    mkdir -p "$out/opt/ctg" \
             "$out/usr/bin" \
             "$out/usr/share/applications"

    cp -a "$TMPDIR/payload/opt/ctg/CtyunClouddeskPublic" "$out/opt/ctg/"
    cp -a "$TMPDIR/payload/usr/bin/ark-update-CtyunClouddeskPublic" \
          "$TMPDIR/payload/usr/bin/ark-update-CtyunClouddeskPublicd" \
          "$out/usr/bin/"
    cp -a "$TMPDIR/payload/usr/share/applications/CtyunClouddeskPublic.desktop" \
          "$out/usr/share/applications/"

    # The vendor ships systemd units under lib/systemd/system; the NixOS
    # module defines equivalent units pointing at our wrappers, so drop the
    # vendor copies to avoid a unit name collision on the system path.
    rm -rf "$TMPDIR/payload/lib"

    APP="$out/opt/ctg/CtyunClouddeskPublic"

    # Re-point desktop entries at absolute store paths (vendor uses
    # /opt/ctg/... which only resolves on the vendor's own layout).
    sed -i \
      -e "s|^Exec=.*|Exec=$out/bin/clouddesktop-qml|" \
      -e "s|^Icon=.*|Icon=$APP/resource/icon-public.png|" \
      "$out/usr/share/applications/CtyunClouddeskPublic.desktop" \
      "$APP/CtyunClouddeskPublic.desktop"

    # System libraries the bundle is missing (see docs/deb-analysis.md,
    # obtained via ldd). The vendored libs come first so they win over any
    # system copy (e.g. the bundle ships its own OpenSSL 1.1 / ICU 55).
    SYS_LIBS="$(makeLibraryPath [
      glibc gcc
      alsa-lib dbus libdrm expat
      fontconfig freetype glib libgudev xz
      nspr nss opus pixman pulseaudio sqlite
      libuuid v4l-utils mesa zlib
      libx11 libxcb libxext libxfixes libxi libxrandr
      libxrender libxscrnsaver libxcomposite libxcursor
      libxdamage libxslt
    ])"

    wrap_bin() {
      local bin="$1" target="$2" extra="${3-}"
      makeWrapper "$APP/$bin" "$out/bin/$target" \
        --prefix LD_LIBRARY_PATH : "$APP/lib:$SYS_LIBS" \
        --prefix PATH : "$APP/libexec$extra"
    }

    # GUI client (also the .desktop Exec target)
    wrap_bin clouddesktop-qml clouddesktop-qml
    # shared daemon (clouddesktop-daemon.service)
    wrap_bin clouddesktop-daemon clouddesktop-daemon
    # crash report helper spawned by the app
    wrap_bin crashpad_handler crashpad_handler

    # self-update tooling (ark-update-*)
    makeWrapper "$out/usr/bin/ark-update-CtyunClouddeskPublic" \
      "$out/bin/ark-update-CtyunClouddeskPublic" \
      --prefix LD_LIBRARY_PATH : "$SYS_LIBS"
    makeWrapper "$out/usr/bin/ark-update-CtyunClouddeskPublicd" \
      "$out/bin/ark-update-CtyunClouddeskPublicd" \
      --prefix LD_LIBRARY_PATH : "$SYS_LIBS"

    runHook postInstall
  '';

  passthru = {
    inherit srcUrl srcHash;
    appDir = "$out/opt/ctg/CtyunClouddeskPublic";
  };

  meta = with lib; {
    description = "天翼云电脑 (CTyun Cloud PC / AI cloud desktop) client";
    longDescription = ''
      Desktop client for the China Telecom 天翼量子AI云电脑 (CTyun Cloud PC)
      service, extracted from the vendor's Debian binary package
      (package: ctyunclouddeskpublic, version 4.1.0.1346, build 204010003-1346).
      The payload is a prebuilt Qt5/QtWebEngine application under
      /opt/ctg/CtyunClouddeskPublic with a system daemon
      (clouddesktop-daemon) and a self-update daemon (ark-update-*).
      See https://desk.ctyun.cn for the upstream product.
    '';
    homepage = "https://desk.ctyun.cn";
    license = licenses.unfree;
    platforms = platforms.x86_64Linux;
    mainProgram = "clouddesktop-qml";
    maintainers = with maintainers; [ ];
  };
}
