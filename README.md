# rpi4-installer

rpi4-installer is a Raspberry Pi OS installer for USB mass storage device for Raspberry Pi 4.

## Features

* Create a swap partition (optional).
* Install Raspberry Pi OS to LVM.
* Create SSD optimized `fstab`.

## Getting Started

### Prerequisites

In order to boot the Raspberry Pi 4 from USB, it is necessary to upgrade the EEPROM to supports USB mass storage device boot.

```sh
# Require Sep 3 2020 or later
$ vcgencmd bootloader_version
Sep  3 2020 13:11:43
version c305ZZ1a6d7e532693cc7ff57fddfc8649def167 (release)
timestamp 1599135103
```

If not, upgrade it.

```sh
$ sudo apt update
$ sudo apt full-upgrade
$ sudo reboot
```

After reboot, set USB device as a primary boot devise (and microSD as a secondary).

```sh
$ sudo raspi-config
```

### Installation

1. Download Raspberry Pi OS and install to a microSD.
2. Boot Raspberry Pi 4 from a microSD.
3. Open a terminal and type commands:
   ```sh
   $ cd /run/shm
   $ wget https://raw.githubusercontent.com/nowlinuxing/rpi4-installer/main/rpi4-install.sh
   $ sh ./rpi4-install.sh
   ```
4. Shutdown the Raspberry Pi 4, remove the microSD, and boot the device.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
