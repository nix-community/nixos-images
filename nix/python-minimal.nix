{
  nixpkgs.overlays = [
    (final: prev: {
      bcachefs-tools = prev.bcachefs-tools.override { python3 = final.python3Minimal; };
      cifs-utils = prev.cifs-utils.override { python3 = final.python3Minimal; };
      nfs-utils = prev.nfs-utils.override { python3 = final.python3Minimal; };
      talloc = prev.talloc.override { python3 = final.python3Minimal; };
      samba = prev.samba.override { python3Packages = final.python3Minimal.pkgs; };
      tevent = prev.tevent.override { python3 = final.python3Minimal; };
      tdb = prev.tdb.override { python3 = final.python3Minimal; };
      ldb = prev.ldb.override { python3 = final.python3Minimal; };
    })
  ];
}
