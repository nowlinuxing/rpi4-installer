#!/bin/sh

ROOT_PARTNUM=2
VG_NAME="pi-vg"

PART_SIZE_BOOT="256M"


clear_device() {
  local dev=$1

  vgs | awk 'NR>=2{print $1}' | while read vg; do
    echo "Remove volume group: ${vg}"
    vgremove -y $vg
  done

  pvs | awk 'NR>=2{print $1}' | while read pv; do
    echo "Remove physical volume: ${pv}"
    pvremove -y $pv
  done

  sgdisk --zap-all $dev
}

calc_pv_size_gigabytes() {
  local disk_info="$1"
  local part_num=$2

  local sector_size=$(echo "$disk_info" | sed -n 's|Sector size (logical/physical): [0-9]*/\([0-9]*\).*|\1|p')

  set $(echo "$disk_info" | sed -n '/^Number /,$p' | awk -v part_num=$part_num '$1 == part_num { print $2, $3 }')
  local sector_start=$1
  local sector_end=$2

  expr \( $sector_end - $sector_start \) \* $sector_size / \( 1024 \* 1024 \* 1024 \)
}


while [ ! -b "$target_dev" ]; do
  read -p "Target device [/dev/sda]: " target_dev
  target_dev=${target_dev:-/dev/sda}
done

mount | sed -n "s|^\(${target_dev}[1-9][0-9]*\).*|\1|p" | xargs -r umount

# Inspect device partitions
n_partitions=$(gdisk -l $target_dev | sed -n '/^Number /,$p' | tail -n +2 | wc -l)
if [ $n_partitions -gt 0 ]; then
  echo "Partition(s) available."
  while [ "$is_remove" != "y" -a "$is_remove" != "n" ]; do
    read -p "Remove anyway? [y/N]: " is_remove
    is_remove=${is_remove:-n}
  done

  if [ "$is_remove" = "y" ]; then
    clear_device $target_dev
  else
    echo "Abort."
    exit 1
  fi
fi

while [ "$install_to_ssd" != "y" -a "$install_to_ssd" != "n" ]; do
  read -p "Install to SSD? [y/N]: " install_to_ssd
  install_to_ssd=${install_to_ssd:-n}
done

while [ "$create_swap" != "y" -a "$create_swap" != "n" ]; do
  read -p "Create a swap partition? [y/N]: " create_swap
  create_swap=${create_swap:-n}
done

if [ "$create_swap" = "y" ]; then
  while [ -z "$(echo $part_size_swap_gigabytes | grep -E '^[1-9][0-9]{0,2}$')" ]; do
    read -p "Swap partition size in GB [8]: " part_size_swap_gigabytes
    part_size_swap_gigabytes=${part_size_swap_gigabytes:-8}
  done
fi

dev_boot="${target_dev}1"
dev_lvm="${target_dev}${ROOT_PARTNUM}"

echo
echo "Create partitions."
echo
sgdisk -n 1::+${PART_SIZE_BOOT} -t 1:0700               $target_dev
sgdisk -n ${ROOT_PARTNUM}::0    -t ${ROOT_PARTNUM}:8300 $target_dev

echo
echo "Create a physical volume."
echo
pvcreate -y $dev_lvm

echo
echo "Create a volume group."
echo
vgcreate -y ${VG_NAME} $dev_lvm

echo
echo "Create logical volumes."
echo
disk_info=$(gdisk -l $target_dev)
if [ "$create_swap" = "y" ]; then
  pv_size_gigabytes=$(calc_pv_size_gigabytes "$disk_info" $ROOT_PARTNUM)

  root_size=$(expr $pv_size_gigabytes - $part_size_swap_gigabytes)
  lvcreate --size ${root_size}G --name root -y ${VG_NAME}
  lvcreate -l 100%FREE          --name swap -y ${VG_NAME}
else
  lvcreate -l 100%FREE          --name root -y ${VG_NAME}
fi

echo
echo "Format partitions."
echo
dev_root="/dev/${VG_NAME}/root"
dev_swap="/dev/${VG_NAME}/swap"
mkfs -t vfat $dev_boot
mkfs -t ext4 -F $dev_root
if [ "$create_swap" = "y" ]; then
  mkswap $dev_swap
fi

echo
echo "Copy system files."
echo
mntpt_root=/tmp/root

[ -d $mntpt_root ] || mkdir $mntpt_root
mount $dev_root $mntpt_root
(
  cd /
  dirs=$( ls -1 | grep -v -e dev  \
                       -v -e sys  \
                       -v -e proc \
                       -v -e run  \
                       -v -e boot \
                       -v -e tmp \
                       -v -e lost+found
        )
  cp -a $dirs $mntpt_root/
  cd $mntpt_root
  mkdir dev sys proc run boot tmp
)

mntpt_boot=/tmp/root/boot
mount $dev_boot $mntpt_boot
cp -a /boot/* $mntpt_boot/

echo
echo "Change fstab."
echo
boot_partuuid_str=$(blkid -o export $dev_boot | grep PARTUUID)
if [ "$install_to_ssd" = "y" ]; then
  root_part_defaults="defaults,noatime"
else
  root_part_defaults="defaults"
fi
cat << FSTAB > $mntpt_root/etc/fstab
proc            /proc           proc    defaults          0       0
$boot_partuuid_str  /boot           vfat    defaults          0       2
$dev_root  /               ext4    ${root_part_defaults}  0       1
FSTAB

if [ "$create_swap" = "y" ]; then
  echo "$dev_swap  none            swap    sw  0       0" >> $mntpt_root/etc/fstab
fi

echo
echo "Change boot settings."
echo
sed -i.bak "s|root=[^ ]*|root=$dev_root initrd=0x01f00000|" $mntpt_boot/cmdline.txt

echo
echo "Create initramfs."
echo
mount --bind /sys  $mntpt_root/sys
mount --bind /proc $mntpt_root/proc
mount --bind /dev  $mntpt_root/dev

chroot $mntpt_root apt install lvm2
chroot $mntpt_root mkinitramfs -o /boot/initrd.gz

echo "initramfs initrd.gz 0x01f00000" >> $mntpt_root/boot/config.txt

umount $mntpt_root/sys
umount $mntpt_root/proc
umount $mntpt_root/dev

umount $mntpt_root/boot
umount $mntpt_root

echo "Done."
