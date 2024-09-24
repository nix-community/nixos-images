{
  nixpkgs.overlays = [
    (final: prev: {
      bcachefs-tools = prev.bcachefs-tools.overrideAttrs (old: {
        python3 = prev.python3Minimal;
      });
      cifs-utils = prev.cifs-utils.overrideAttrs (old: {
        python3 = prev.python3Minimal;
      });
      nfs-utils = prev.nfs-utils.overrideAttrs (old: {
        python3 = prev.python3Minimal;
      });
    })
  ];
}
