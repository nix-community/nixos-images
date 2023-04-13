# This module optimizes for deployments to virtualized hosts.

{ lib, ... }: {
  hardware.enableRedistributableFirmware = lib.mkForce false;
}
