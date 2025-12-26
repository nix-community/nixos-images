{
  nixpkgs.overlays = [
    (final: prev: {
      nfs-utils = prev.nfs-utils.override { python3 = final.python3Minimal; };
    })
  ];
}
