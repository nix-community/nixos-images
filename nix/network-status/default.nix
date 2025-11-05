{ lib
, rustPlatform
, features ? []
}:

rustPlatform.buildRustPackage rec {
  pname = "network-status";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # Only build with features if specified
  buildFeatures = features;

  meta = with lib; {
    description = "Display QR code and network status on framebuffer or terminal";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "network-status";
  };
}