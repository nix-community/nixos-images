{ lib
, rustPlatform
, resvg
, graphicsmagick
, features ? []
}:

rustPlatform.buildRustPackage rec {
  pname = "network-status";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # resvg and graphicsmagick needed by build.rs to rasterize logo
  nativeBuildInputs = [ resvg graphicsmagick ];

  # Only build with features if specified
  buildFeatures = features;

  meta = with lib; {
    description = "Display QR code and network status on framebuffer or terminal";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "network-status";
  };
}