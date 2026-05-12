-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (quilt)
Source: wpewebkit
Binary: libwpewebkit-2.0-dev, libwpewebkit-2.0-1, wpewebkit-webdriver, libwpewebkit-doc, libwpewebkit-1.0-doc, wpewebkit-driver
Architecture: linux-any all
Version: 2.48.3-1
Maintainer: Debian WebKit Maintainers <pkg-webkit-maintainers@lists.alioth.debian.org>
Uploaders: Alberto Garcia <berto@igalia.com>
Homepage: https://wpewebkit.org/
Standards-Version: 4.7.2
Vcs-Browser: https://salsa.debian.org/webkit-team/webkit
Vcs-Git: https://salsa.debian.org/webkit-team/webkit.git -b wpe/unstable
Build-Depends: dpkg-dev (>= 1.22.5), debhelper-compat (= 13), bubblewrap [amd64 arm64 armel armhf i386 mips64el ppc64el riscv64 s390x hppa ppc64 x32], xdg-dbus-proxy [amd64 arm64 armel armhf i386 mips64el ppc64el riscv64 s390x hppa ppc64 x32], libseccomp-dev [amd64 arm64 armel armhf i386 mips64el ppc64el riscv64 s390x hppa ppc64 x32], cmake (>= 3.16), flite1-dev, gperf, libatk-bridge2.0-dev, libatk1.0-dev, libavif-dev, libcairo2-dev, libepoxy-dev, libgbm-dev, libgcrypt20-dev, libgstreamer-plugins-bad1.0-dev, libgstreamer-plugins-base1.0-dev, libgstreamer1.0-dev, libharfbuzz-dev, libicu-dev, libjpeg-dev, libjxl-dev, liblcms2-dev, libopenjp2-7-dev, libsoup-3.0-dev, libsqlite3-dev, libsystemd-dev, libtasn1-6-dev, libwayland-dev, libwebp-dev, libwoff-dev, libwpe-1.0-dev, libwpebackend-fdo-1.0-dev, libxslt1-dev, ninja-build, ruby:native, unifdef, wayland-protocols
Build-Depends-Indep: gi-docgen, gobject-introspection, libgirepository1.0-dev, libglib2.0-doc, libsoup-3.0-doc, jdupes
Package-List:
 libwpewebkit-1.0-doc deb oldlibs optional arch=all profile=!nodoc
 libwpewebkit-2.0-1 deb libs optional arch=linux-any
 libwpewebkit-2.0-dev deb libdevel optional arch=linux-any
 libwpewebkit-doc deb doc optional arch=all profile=!nodoc
 wpewebkit-driver deb oldlibs optional arch=all
 wpewebkit-webdriver deb web optional arch=linux-any
Checksums-Sha1:
 8a90b9ff8809c99c306defc1a08e50a31a09c590 42211124 wpewebkit_2.48.3.orig.tar.xz
 aad51f427f80d494cfd9237a23dc715a8ed5dc0a 195 wpewebkit_2.48.3.orig.tar.xz.asc
 36ad5cdd98c2bc0fad2a8472116fd6404b67084f 50100 wpewebkit_2.48.3-1.debian.tar.xz
Checksums-Sha256:
 807571f07e87823b8fb79564692c9b1ef81ee62edbf51345a15bd0e7e1f2e07b 42211124 wpewebkit_2.48.3.orig.tar.xz
 abb7fc0c67f93b8ed57580486b3f065a4117dcaff980e4ab4df4dcf133c33f8e 195 wpewebkit_2.48.3.orig.tar.xz.asc
 ed7ce0b8f51db84b7a22cec65abc8ea867ba9cb790e39a2602c89234e4b4dfb9 50100 wpewebkit_2.48.3-1.debian.tar.xz
Files:
 2d3b7fa3c62886546f918fcc289cabbe 42211124 wpewebkit_2.48.3.orig.tar.xz
 ad03c703ff24375ce195f0f136a851ff 195 wpewebkit_2.48.3.orig.tar.xz.asc
 7b7f8bd7a12f577b431c20289a9b3e6f 50100 wpewebkit_2.48.3-1.debian.tar.xz

-----BEGIN PGP SIGNATURE-----

iQIzBAEBCgAdFiEEYrwugQBKzlHMYFizAAyEYu0C2AIFAmg5asUACgkQAAyEYu0C
2AJCFw//cgAo1SnhQayuNVPxF55+KXDK/FKNF2zj1MXVYElS1aC+v9eVAVHBkMun
1m5J03uRxjjbBXTvmWbyegzQ6ihzZfiLExAhOl5vNHEKHh9xvpY0VjY4kCCZs/w9
PfPzDBiXRie9qcV6G5nZ1pvmbNiJjKTvrRPwsobFz/m9Zu2lppXi/npkJOb6aqtC
lqjxurxGSdhk/P2bNudCl1pfJB0DDTCYWLbmYGtTe1gwsH2NMIUznPYQoKjO/PdJ
Jl24y4LAkSRs/r8IfEvtByUxlam69BNtq+5fwv/YymnxFRZhgSatRbSxMkCbd9bF
r15XcgKtxXn5ajxbEYy1myFPkxXTWVhU2dy4S7UcH2kyjUT6QiXo3yhAnZB9SlNw
4HbTsfFRYf9C0AJ8nPN4oCiSBZRquuCcK0WcyGdSzRFnuxIE9bBsN8i1pNMuWKaY
Rd+yq9goYV8+yX72KGvlTVUdpX5Va+tujp99R9GfW6dnwRveAcyEsMGvCSsVwYO0
gZKz1t56vOgPORMqghPwS2/QGmIReM+0DQKEqkBVrnXsrsyXf/tJ5/huB8jX6Dbh
HnyQaW8IxQrP/4Y12RYVqf/n8Db3xfT+7o9DA0qJhAOPIIIIWWrJR3sJbw6qqWsk
cMNP/0yqmQGA6l1sGdfcXaoG/0Gl+CGRV8o5xE+FYNjbfz6E+yI=
=xyXy
-----END PGP SIGNATURE-----
