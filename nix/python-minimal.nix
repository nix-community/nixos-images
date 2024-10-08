{
  nixpkgs.overlays = [
    (final: prev: {
      bcachefs-tools = prev.bcachefs-tools.override { python3 = final.python3Minimal; };
      cifs-utils = prev.cifs-utils.override { python3 = final.python3Minimal; };
      nfs-utils = prev.nfs-utils.override { python3 = final.python3Minimal; };
      talloc = prev.talloc.override { python3 = final.python3Minimal; };
    })
  ];
}
