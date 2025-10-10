mkdir root
mkdir root/EFI
mkdir root/EFI/BOOT
mkdir ~/qemu_uefi
mkdir ~/qemu_uefi/OVMF/
cp /usr/share/OVMF/OVMF_VARS.fd ~/qemu_uefi/OVMF/
echo 'Execute: sudo chown $USER:$USER ~/qemu_uefi/OVMF/OVMF_VARS.fd'
echo 'Execute: sudo chmod 600 ~/qemu_uefi/OVMF/OVMF_VARS.fd'
